#!/bin/bash
# distill-l3/run.sh — 全局蒸馏 + 按项目精炼
set -euo pipefail
cd "$VAULT_ROOT"
source "$VAULT_ROOT/core/jj-utils.sh"
jj git init --colocate 2>/dev/null || true

L2_DIR="$VAULT_ROOT/distilled/L2"
L3_DIR="$VAULT_ROOT/distilled/L3"
mkdir -p "$L3_DIR/projects"

# ── 全局蒸馏 (合并所有 L2) ──
ALL_L2=""
for f in "$L2_DIR"/*.md; do
  [ -f "$f" ] || continue
  proj=$(basename "$f" .md)
  [ "$proj" = "_meta" ] && continue
  ALL_L2+="
=== 项目: $proj ===
$(cat "$f")
"
done

if [ -z "$ALL_L2" ]; then
  echo "No L2 output, skipping L3"
  exit 0
fi

DATE=$(date +%F)

echo "=== L3: Global unified ==="
gemini -p "$(cat <<PROMPT
你是全局知识蒸馏引擎。合并所有项目摘要为一份全局参考文档。

## ⚠️ 硬上限: 3000 字。超出则压缩项目概览。

$ALL_L2

## 输出格式

# 统一记忆 — $DATE

## 用户画像
- 技术栈偏好、工作习惯 (从所有项目总结,≤200字)

## 全局约定
- 跨项目通用规范 (≤300字)

## 各项目状态
### {项目名}
- 定位 | 状态 (活跃/维护/暂停) | 关键决策 (≤3条) | 待办

## 关键排错经验
- 跨项目通用的坑和方案 (≤500字)

总字数 ≤ 3000。只输出 Markdown。
PROMPT
)" > "$L3_DIR/unified.md"
echo "  unified.md: $(wc -l < "$L3_DIR/unified.md") lines"

# ── 按项目精炼 (每个 L2 项目单独精炼) ──
echo "=== L3: Per-project ==="
for f in "$L2_DIR"/*.md; do
  [ -f "$f" ] || continue
  proj=$(basename "$f" .md)
  [ "$proj" = "_meta" ] && continue
  [ "$proj" = "_global" ] && continue

  echo "  Project: $proj"
  PROJ_CONTENT=$(cat "$f")

  gemini -p "$(cat <<PROMPT
精炼以下项目记忆。保留所有关键信息,但总字数 ≤ 800 (排错经验除外)。

$PROJ_CONTENT

# $proj — $DATE
## 项目定位 (一句话)
## 架构决策 (按重要性,≤5条)
## 技术约定
## 已解决的问题 (不限字数,这是最有价值的信息)
## 当前状态与待办
PROMPT
)" > "$L3_DIR/projects/$proj.md"
  sleep 3
done

echo "L3 complete"
