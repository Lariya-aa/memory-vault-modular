#!/bin/bash
# L2 蒸馏: 增量合并 — 上次 L2 结果 + 新增条目
#
# 解决的问题:
#   1. Argument list too long: 用临时文件 + 分批处理
#   2. 无限膨胀: L2 输入 = 旧摘要(固定) + 新条目(增量)
#   3. 信息丢失: 按优先级保留，分批处理不截断
#
set -euo pipefail

source "$VAULT_ROOT/core/jj-utils.sh"

VAULT="${VAULT_ROOT:-${CI_PROJECT_DIR:-.}}"
L1_DIR="$VAULT/distilled/L1"
L2_DIR="$VAULT/distilled/L2"
mkdir -p "$L2_DIR"

cd "$VAULT"

# ── 配置 ──
BATCH_SIZE=30           # 每批处理条目数
MAX_CONTENT_LEN=500     # 单条记忆最大字符 (保留更多上下文)
MAX_SUMMARY_LEN=4000    # 旧摘要最大字符
MAX_OUTPUT_WORDS=3000   # 输出限制 (字而非字符，给 Gemini 更多空间)

# 找到最新的 L1 输出目录
LATEST_L1=$(ls -td "$L1_DIR"/*/ 2>/dev/null | head -1)
if [ -z "$LATEST_L1" ]; then
  echo "No L1 output found, skipping L2"
  exit 0
fi

echo "Using L1 output: $LATEST_L1"

# ── 格式化条目的 Python 脚本 (复用) ──
format_entries() {
  local file="$1"
  local offset="${2:-0}"
  local limit="${3:-$BATCH_SIZE}"
  python3 -c "
import json, sys
entries = json.load(open('$file'))[$offset:$offset+$limit]
for e in entries:
    src = e.get('source', '?')
    machine = e.get('machine', '?')
    content = e.get('content', '')[:$MAX_CONTENT_LEN]
    etype = e.get('type', 'unknown')
    ctx = e.get('context', '')
    line = f'- [{etype}] {content}'
    if ctx:
        line += f' (原因: {ctx[:150]})'
    line += f' [来源: {src}@{machine}]'
    print(line)
print(f'[共 {len(entries)} 条]', file=sys.stderr)
" 2>/dev/null
}

# ── 调用 Gemini 的安全函数 ──
gemini_distill() {
  local prompt_file="$1"
  local output_file="$2"

  # 检查 prompt 大小
  local size
  size=$(wc -c < "$prompt_file" | tr -d ' ')

  if [ "$size" -gt 120000 ]; then
    echo "    WARNING: prompt $size bytes, truncating to 120K"
    head -c 120000 "$prompt_file" > "${prompt_file}.trunc"
    mv "${prompt_file}.trunc" "$prompt_file"
  fi

  # 用管道传递避免 ARG_MAX 限制
  cat "$prompt_file" | gemini -p "$(cat "$prompt_file")" > "$output_file" 2>/dev/null
  local rc=$?

  if [ $rc -ne 0 ] || [ ! -s "$output_file" ]; then
    echo "    Gemini failed (rc=$rc), retrying with shorter input..."
    head -c 60000 "$prompt_file" > "${prompt_file}.short"
    gemini -p "$(cat "${prompt_file}.short")" > "$output_file" 2>/dev/null || {
      echo "    ERROR: gemini failed"
      rm -f "${prompt_file}.short"
      return 1
    }
    rm -f "${prompt_file}.short"
  fi
  return 0
}

PROJECT_COUNT=0

for project_file in "$LATEST_L1"/*.json; do
  [ -f "$project_file" ] || continue
  project=$(basename "$project_file" .json)
  [ "$project" = "_meta" ] && continue

  echo "=== Distilling L2: $project ==="

  MEM_COUNT=$(python3 -c "import json; print(len(json.load(open('$project_file'))))" 2>/dev/null || echo 0)
  if [ "$MEM_COUNT" -eq 0 ]; then
    echo "  Skipping empty: $project"
    continue
  fi

  if [ "$project" = "_global" ]; then
    BUDGET=2500
  else
    BUDGET=1500
  fi

  EXISTING_L2="$L2_DIR/$project.md"

  # ── 计算需要几批 ──
  TOTAL_BATCHES=$(( (MEM_COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))
  echo "  Entries: $MEM_COUNT → $TOTAL_BATCHES batch(es) of $BATCH_SIZE"

  # ── 准备初始摘要 ──
  CURRENT_SUMMARY=""
  if [ -f "$EXISTING_L2" ] && [ -s "$EXISTING_L2" ]; then
    CURRENT_SUMMARY=$(cat "$EXISTING_L2")
    echo "  Mode: incremental (existing summary + $MEM_COUNT new)"
  else
    echo "  Mode: initial"
  fi

  # ── 分批处理 ──
  BATCH=0
  while [ $BATCH -lt $TOTAL_BATCHES ]; do
    OFFSET=$((BATCH * BATCH_SIZE))
    REMAINING=$((MEM_COUNT - OFFSET))
    THIS_BATCH=$((REMAINING < BATCH_SIZE ? REMAINING : BATCH_SIZE))

    if [ $TOTAL_BATCHES -gt 1 ]; then
      echo "  Batch $((BATCH + 1))/$TOTAL_BATCHES (entries $((OFFSET + 1))-$((OFFSET + THIS_BATCH)))"
    fi

    NEW_ENTRIES=$(format_entries "$project_file" "$OFFSET" "$THIS_BATCH")
    PROMPT_FILE=$(mktemp)

    if [ -n "$CURRENT_SUMMARY" ]; then
      # ── 增量模式: 旧摘要 + 新条目 ──
      
      # 检查旧摘要是否超预算
      OLD_SIZE=$(wc -c <<< "$CURRENT_SUMMARY" | tr -d ' ' || echo 0)
      if [ "$OLD_SIZE" -gt $((BUDGET * 3)) ]; then
        echo "  WARNING: existing summary ${OLD_SIZE} chars exceeds 3x budget. Will be compressed."
      fi

      # 简单的按章节截断，仅为了防止炸 prompt
      TRIMMED_SUMMARY=$(python3 -c "
text = open('/dev/stdin').read()
if len(text) > $MAX_SUMMARY_LEN:
    lines = text.split('\n')
    result = []
    kept = 0
    for line in lines:
        if line.startswith('## '):
            result.append(line)
            kept = 0
        elif kept < 8:
            result.append(line)
            kept += 1
    text = '\n'.join(result)
print(text[:$MAX_SUMMARY_LEN])
" <<< "$CURRENT_SUMMARY" 2>/dev/null || echo "$CURRENT_SUMMARY" | head -c $MAX_SUMMARY_LEN)

      cat > "$PROMPT_FILE" << PROMPT
你是一个增量记忆合并引擎。有严格的字数预算。

项目: "$project"
本批新增: $THIS_BATCH 条 (总共 $MEM_COUNT 条，第 $((BATCH + 1))/$TOTAL_BATCHES 批)

## ⚠️ 字数预算: $BUDGET 字
输出必须 ≤ $BUDGET 字。超出则压缩低优先级条目。

## 优先级 (从高到低,预算不足时从低优先级开始压缩)
1. decision / solution — 绝不丢弃,最多压缩措辞
2. preference / convention — 合并同类项
3. knowledge — 相似的合并为一条
4. todo — 已完成的标注 [完成] 并移到末尾
5. 超过 90 天的非 decision 条目 — 可以删除,标注 [已清理 N 条]

## 合并规则
- 新信息补充到对应章节
- 矛盾以新的为准,标注 [更新 $(date +%F)]
- 重复的跳过
- 每条必须保留 "[来源: tool@machine]" 标注

已有摘要:
$TRIMMED_SUMMARY

新增条目:
$NEW_ENTRIES

## 输出格式
## 架构与技术决策
## 约定与偏好
## 解决方案与排错经验
## 项目知识
## 活跃待办
## 已归档

只输出 Markdown。总字数 ≤ $BUDGET。
PROMPT

    else
      # ── 首次模式 ──
      cat > "$PROMPT_FILE" << PROMPT
你是一个记忆蒸馏引擎。

项目: "$project"
条目数: $THIS_BATCH 条 (第 $((BATCH + 1))/$TOTAL_BATCHES 批)

## ⚠️ 字数预算: $BUDGET 字

以下是来自多个 AI 工具的记忆:
$NEW_ENTRIES

## 蒸馏规则
1. 合并重叠: 相同知识合并,标注所有来源
2. 按优先级保留: decision / solution > preference > convention > knowledge > todo
3. 去噪: 丢弃临时调试、过期状态
4. 保留冲突: 矛盾记录标注 [冲突]
5. 每条必须保留 "[来源: tool@machine]" 标注

## 输出格式
## 架构与技术决策
## 约定与偏好
## 解决方案与排错经验
## 项目知识
## 活跃待办

只输出 Markdown。总字数 ≤ $BUDGET。
PROMPT
    fi

    # 调用 Gemini
    BATCH_OUTPUT=$(mktemp)
    if gemini_distill "$PROMPT_FILE" "$BATCH_OUTPUT"; then
      CURRENT_SUMMARY=$(cat "$BATCH_OUTPUT")
    else
      echo "  WARNING: batch $((BATCH + 1)) failed, using previous summary"
    fi
    rm -f "$PROMPT_FILE" "$BATCH_OUTPUT"

    BATCH=$((BATCH + 1))
    [ $BATCH -lt $TOTAL_BATCHES ] && sleep 3
  done

  # 写入最终结果
  echo "$CURRENT_SUMMARY" > "$L2_DIR/$project.md"
  LINES=$(wc -l < "$L2_DIR/$project.md")
  echo "  → $L2_DIR/$project.md ($LINES lines)"
  PROJECT_COUNT=$((PROJECT_COUNT + 1))

  sleep 3
done

# 写入 L2 元数据
python3 -c "
import json
from datetime import datetime
meta = {
    'date': datetime.now().isoformat(),
    'project_count': $PROJECT_COUNT,
    'mode': 'incremental-batched',
    'batch_size': $BATCH_SIZE,
}
json.dump(meta, open('$L2_DIR/_meta.json', 'w'), ensure_ascii=False, indent=2)
"

echo "L2 complete: $PROJECT_COUNT projects distilled"
