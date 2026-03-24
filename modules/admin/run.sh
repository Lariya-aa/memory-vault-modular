#!/bin/bash
# jj-admin.sh — jj 管理工具，利用 jj 独特特性做记忆仓库管理
#
# 命令:
#   op-log       — 查看跨机器操作历史 (jj operation log)
#   split        — 按工具拆分混合收割 change (jj split)
#   undo         — 回滚上一次操作 (jj undo)
#   squash-distills — 合并连续蒸馏 change (jj squash)
#   trace        — 追踪某条记忆的来源 change 链
#   status       — 查看 bookmark 进度和仓库状态
#   diff-since   — 查看自某次蒸馏以来的所有变更
#   gc           — 清理过期的 L1 蒸馏输出
#
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-${MEMORY_VAULT:-$HOME/memory-vault}}"
source "$VAULT_ROOT/core/jj-utils.sh"

VAULT="${MEMORY_VAULT:-$HOME/memory-vault}"
cd "$VAULT"

case "${1:-help}" in

  # ── jj op log: 仓库级审计，查看所有机器的操作 ──
  op-log)
    COUNT="${2:-30}"
    echo "=== Operation Log (last $COUNT ops) ==="
    echo "jj 特性: op log 是仓库级的，能看到所有机器的操作"
    echo ""
    jj op log --limit "$COUNT"
    ;;

  # ── jj split: 按工具拆分混合收割 ──
  split)
    CHANGE="${2:?Usage: jj-admin.sh split <change-id>}"
    echo "=== Splitting change $CHANGE by tool ==="
    echo "jj 特性: split 可以交互式选择哪些文件归哪个 change"
    echo ""
    echo "当前 change 包含的文件:"
    jj diff -r "$CHANGE" --name-only
    echo ""
    echo "建议按以下方式拆分:"
    echo "  1. raw/claude/  → harvest: <machine> claude"
    echo "  2. raw/gemini/  → harvest: <machine> gemini"
    echo "  3. raw/antigravity/ → harvest: <machine> antigravity"
    echo "  4. raw/openclaw/ → harvest: <machine> openclaw"
    echo ""

    # 编辑到目标 change
    jj edit "$CHANGE"

    # 按目录前缀自动拆分
    for tool in claude gemini antigravity openclaw codex; do
      FILES=$(jj diff --name-only | grep "raw/$tool/" || true)
      if [ -n "$FILES" ]; then
        echo "Splitting out $tool files..."
        # jj split <paths>: 指定文件归入第一个 change，其余留在第二个
        # shellcheck disable=SC2086
        jj split $FILES
        jj describe -m "harvest: split — $tool $(date +%F)"
        jj new
      fi
    done

    # 回到最新
    jj new @
    echo "Split complete. Check with: jj log"
    ;;

  # ── jj undo: 一键回滚上一次操作 ──
  undo)
    echo "=== Undo last operation ==="
    echo "jj 特性: undo 可以撤回任何操作 (commit, push, merge, etc.)"
    echo ""
    echo "上一次操作:"
    jj op log --limit 1
    echo ""
    read -p "确认回滚? (y/N) " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      jj undo
      echo "Done. 如果已 push，需要再次 push: jj git push --allow-new"
    else
      echo "Cancelled"
    fi
    ;;

  # ── jj squash: 合并连续的蒸馏 change ──
  squash-distills)
    echo "=== Squashing consecutive distill changes ==="
    echo "jj 特性: squash 合并 change，保持历史整洁"
    echo ""

    # 找到最近的蒸馏 change
    DISTILL_CHANGES=$(jj log --no-graph \
      -T 'if(description.contains("type: distill"), change_id ++ " " ++ description.first_line() ++ "\n")' \
      | head -10)

    if [ -z "$DISTILL_CHANGES" ]; then
      echo "No distill changes found"
      exit 0
    fi

    echo "Recent distill changes:"
    echo "$DISTILL_CHANGES"
    echo ""
    echo "Squashing into single change..."

    # 获取最旧和最新的蒸馏 change
    OLDEST=$(echo "$DISTILL_CHANGES" | tail -1 | awk '{print $1}')
    NEWEST=$(echo "$DISTILL_CHANGES" | head -1 | awk '{print $1}')

    if [ "$OLDEST" != "$NEWEST" ]; then
      jj squash --from "$OLDEST" --into "$NEWEST"
      jj describe -r "$NEWEST" -m "distill: squashed $(echo "$DISTILL_CHANGES" | wc -l) changes $(date +%F)"
      echo "Squashed. Check with: jj log"
    else
      echo "Only one distill change, nothing to squash"
    fi
    ;;

  # ── 追踪某条记忆的来源 change 链 ──
  trace)
    CHANGE="${2:?Usage: jj-admin.sh trace <change-id>}"
    echo "=== Tracing change $CHANGE ==="
    echo ""

    # 显示 change 详情
    echo "--- Change Info ---"
    jj log -r "$CHANGE" --no-graph -T 'concat(
      "Change ID: ", change_id, "\n",
      "Commit ID: ", commit_id, "\n",
      "Author: ", author.name(), "\n",
      "Timestamp: ", author.timestamp(), "\n",
      "\n",
      description, "\n"
    )'

    echo ""
    echo "--- Files Changed ---"
    jj diff -r "$CHANGE" --stat

    echo ""
    echo "--- Related Operations ---"
    jj op log --limit 50 2>/dev/null | grep -A1 "$CHANGE" || echo "(not found in recent op log)"
    ;;

  # ── 查看 bookmark 进度和仓库状态 ──
  status)
    echo "=== Memory Vault Status ==="
    echo ""

    echo "--- Bookmarks (蒸馏进度) ---"
    jj bookmark list 2>/dev/null || echo "(no bookmarks)"

    echo ""
    echo "--- Recent Changes ---"
    jj log --limit 10

    echo ""
    echo "--- Harvest Statistics ---"
    HARVEST_COUNT=$(jj log --no-graph \
      -T 'if(description.contains("type: harvest"), "x\n")' 2>/dev/null \
      | wc -l | tr -d ' ')
    DISTILL_COUNT=$(jj log --no-graph \
      -T 'if(description.contains("type: distill"), "x\n")' 2>/dev/null \
      | wc -l | tr -d ' ')
    echo "Total harvests: $HARVEST_COUNT"
    echo "Total distills: $DISTILL_COUNT"

    echo ""
    echo "--- Working Copy ---"
    jj status
    ;;

  # ── 查看自某次蒸馏以来的所有变更 ──
  diff-since)
    BOOKMARK="${2:-distilled-l1}"
    echo "=== Changes since bookmark: $BOOKMARK ==="
    if jj bookmark list 2>/dev/null | grep -q "^$BOOKMARK:"; then
      jj log -r "$BOOKMARK..@"
      echo ""
      echo "--- File Summary ---"
      jj diff -r "$BOOKMARK..@" --stat 2>/dev/null || \
        echo "(diff across range not supported, showing individual changes above)"
    else
      echo "Bookmark '$BOOKMARK' not found. Available:"
      jj bookmark list
    fi
    ;;

  # ── 清理过期 L1 输出 ──
  gc)
    KEEP_DAYS="${2:-7}"
    echo "=== Garbage Collection (keeping last $KEEP_DAYS days) ==="

    if [[ "$(uname)" == "Darwin" ]]; then
      cutoff=$(date -v-${KEEP_DAYS}d +%F)
    else
      cutoff=$(date -d "$KEEP_DAYS days ago" +%F)
    fi

    # 清理 L1 蒸馏输出
    L1_DIR="$VAULT/distilled/L1"
    DELETED=0
    if [ -d "$L1_DIR" ]; then
      for dir in "$L1_DIR"/*/; do
        dir_date=$(basename "$dir")
        if [[ "$dir_date" < "$cutoff" ]]; then
          rm -rf "$dir"
          DELETED=$((DELETED + 1))
          echo "  L1 removed: $dir_date"
        fi
      done
    fi

    # 清理对话归档 (conversations/)
    CONV_DELETED=0
    for tool_dir in "$VAULT"/conversations/*/; do
      for machine_dir in "$tool_dir"*/; do
        for date_dir in "$machine_dir"*/; do
          dir_date=$(basename "$date_dir")
          if [[ "$dir_date" < "$cutoff" ]]; then
            rm -rf "$date_dir"
            CONV_DELETED=$((CONV_DELETED + 1))
          fi
        done
      done
    done

    # 清理 harvest-log (保留最近 1000 行)
    HLOG="$VAULT/.harvest-log.jsonl"
    if [ -f "$HLOG" ] && [ "$(wc -l < "$HLOG")" -gt 1000 ]; then
      tail -500 "$HLOG" > "$HLOG.tmp" && mv "$HLOG.tmp" "$HLOG"
      echo "  harvest-log trimmed to 500 entries"
    fi

    echo "Cleaned: $DELETED L1 dirs, $CONV_DELETED conversation dirs"

    # jj util gc: 清理 jj 内部存储
    jj util gc 2>/dev/null && echo "  jj store gc done" || true
    ;;

  help|*)
    cat <<HELP
Memory Vault jj Admin — 利用 jj 特性管理记忆仓库

用法: bash scripts/jj-admin.sh <command> [args]

命令 (jj 特性):
  op-log [count]           查看跨机器操作历史 (jj operation log)
  split <change-id>        按工具拆分混合收割 (jj split)
  undo                     回滚上一次操作 (jj undo)
  squash-distills          合并连续蒸馏 change (jj squash)
  trace <change-id>        追踪记忆来源 (jj log + change ID)
  status                   查看 bookmark 进度 (jj bookmark)
  diff-since [bookmark]    查看自某次蒸馏的变更 (jj diff)
  gc [days]                清理过期 L1 输出

示例:
  jj-admin.sh status                    # 查看仓库状态
  jj-admin.sh op-log 50                 # 查看最近50条操作
  jj-admin.sh split xyzabc              # 拆分混合收割
  jj-admin.sh trace xyzabc              # 追踪某次收割
  jj-admin.sh squash-distills           # 合并蒸馏历史
  jj-admin.sh undo                      # 回滚上次操作
  jj-admin.sh diff-since distilled-l2   # L2 以来的变更
  jj-admin.sh gc 14                     # 保留14天 L1
HELP
    ;;
esac
