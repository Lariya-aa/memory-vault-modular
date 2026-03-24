#!/bin/bash
# distill-l0/distill.sh — Gemini CLI 蒸馏对话 (按项目)
set -euo pipefail

cd "$VAULT_ROOT"
L0_DIR="$VAULT_ROOT/distilled/L0"

LATEST_L0=$(ls -td "$L0_DIR"/*/ 2>/dev/null | head -1)
if [ -z "$LATEST_L0" ]; then
  echo "No conversations extracted, skipping"
  exit 0
fi

DISTILLED_DIR="$LATEST_L0/_distilled"
mkdir -p "$DISTILLED_DIR"

SESSION_COUNT=0
SKIPPED=0

for session_file in "$LATEST_L0"/*.md; do
  [ -f "$session_file" ] || continue
  filename=$(basename "$session_file" .md)

  CHAR_COUNT=$(wc -c < "$session_file" | tr -d ' ')
  if [ "$CHAR_COUNT" -lt 500 ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "  Distilling: $filename ($CHAR_COUNT chars)"
  CONVERSATION=$(cat "$session_file")

  RESULT=$(gemini -p "$(cat <<PROMPT
你是一个精准的知识提取引擎。从 AI 工具对话中提取**长期可复用**的知识。

对话内容:
$CONVERSATION

## 提取什么 (YES)
- **decision**: 用户明确做出的技术/架构选择 (如 "用 PostgreSQL 而非 MySQL")
- **preference**: 用户表达的偏好/习惯 (如 "不喜欢 TailwindCSS")
- **convention**: 确立的约定/规范 (如 "API 路由统一 /api/v1")
- **knowledge**: 非显而易见的事实 (如 "Node.js 22 的 fetch 忽略 HTTPS_PROXY")
- **todo**: 明确提到但未完成的任务
- **solution**: 经排错确认有效的最终解决方案

## 绝对不提取 (NO)
- 中间调试过程和失败尝试
- AI 的工具调用/文件读取/命令执行细节
- 代码具体实现 (属于版本控制)
- "用户问了 X"/"AI 回答了 Y" 流水账
- 已被否定/推翻的结论
- 通用常识 (如 "Python 用 pip 安装包")

## 质量门槛
提取前自问: "6 个月后换一个 AI 工具,这条信息还有用吗?" 否则不提取。
每条 content 不超过 100 字。宁少勿多,一个对话提取 0-5 条。

输出 JSON 数组 (无 Markdown 代码块):
[{"type": "decision", "content": "简洁内容 (≤100字)", "context": "原因", "scope": "global 或项目名", "confidence": "confirmed/tentative"}]

无可提取知识则输出: []
PROMPT
)" 2>/dev/null || echo "[]")

  if echo "$RESULT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "$RESULT" > "$DISTILLED_DIR/$filename.json"
  else
    CLEANED=$(echo "$RESULT" | python3 -c "
import sys, re, json
text = sys.stdin.read()
match = re.search(r'\[.*\]', text, re.DOTALL)
if match:
    try:
        json.loads(match.group())
        print(match.group())
    except: print('[]')
else: print('[]')
" 2>/dev/null || echo "[]")
    echo "$CLEANED" > "$DISTILLED_DIR/$filename.json"
  fi
  SESSION_COUNT=$((SESSION_COUNT + 1))
  sleep 3
done

# 合并结果
python3 -c "
import json
from pathlib import Path

distilled_dir = Path('$DISTILLED_DIR')
all_entries = []
for f in sorted(distilled_dir.glob('*.json')):
    if f.stem == '_meta': continue
    parts = f.stem.split('-', 2)
    tool = parts[0] if len(parts) > 0 else 'unknown'
    machine = parts[1] if len(parts) > 1 else 'unknown'
    try:
        entries = json.loads(f.read_text())
        if not isinstance(entries, list): continue
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get('content'): continue
            entry['source'] = tool
            entry['machine'] = machine
            entry['origin'] = 'conversation'
            all_entries.append(entry)
    except: pass

output = distilled_dir.parent / '_l0_merged.json'
output.write_text(json.dumps(all_entries, ensure_ascii=False, indent=2))
print(f'L0 merged: {len(all_entries)} entries from {len(list(distilled_dir.glob(\"*.json\")))} sessions')
"

echo "L0 complete: $SESSION_COUNT processed, $SKIPPED skipped"
