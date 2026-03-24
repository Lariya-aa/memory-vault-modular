#!/bin/bash
# init-templates.sh — 初始化配置模板 (只需在一台机器上运行一次)
#
# 用法:
#   bash modules/sync-config/init-templates.sh
#
# 运行后会在 configs/_templates/ 生成所有工具的集成模板。
# 你可以编辑这些模板，push 到 GitLab 后，所有机器自动注入。
#
set -euo pipefail

VAULT_ROOT="${VAULT_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TEMPLATES_DIR="$VAULT_ROOT/configs/_templates"
MARKER="<!-- memory-vault-managed -->"

mkdir -p "$TEMPLATES_DIR"
echo "=== 初始化配置模板 ==="
echo "输出: $TEMPLATES_DIR"
echo ""

# ── Claude CLI 全局 ──
cat > "$TEMPLATES_DIR/claude-global.md" << EOF
$MARKER
## Memory Vault 跨工具记忆系统

本机已部署 memory-vault 跨工具记忆同步系统。

### 你应该知道的:
- 你的记忆文件 (\`~/.claude/memory/\`) 每30分钟自动同步到 memory-vault
- 其他工具 (Gemini/Antigravity/OpenClaw/Codex) 的蒸馏知识会自动出现在
  \`~/.claude/memory/cross_tool_context.md\` 中
- 按项目的跨工具知识会出现在对应项目的 memory 目录中

### 最佳实践:
- 重要决策请写入 memory (type: feedback 或 project), 它们会被跨工具同步
- 不需要手动管理跨工具同步, 系统自动处理
- \`cross_tool_context.md\` 是自动生成的, 不要手动编辑
$MARKER
EOF
echo "  claude-global.md ✓"

# ── Claude CLI 项目级 ──
cat > "$TEMPLATES_DIR/claude-project.md" << EOF
$MARKER
## 跨工具上下文

本项目通过 memory-vault 与其他 AI 工具 (Gemini/Antigravity/OpenClaw/Codex) 共享知识。
跨工具蒸馏的记忆会自动出现在本项目的 memory 目录中的 \`cross_tool_context.md\`。
$MARKER
EOF
echo "  claude-project.md ✓"

# ── Gemini CLI 全局 ──
cat > "$TEMPLATES_DIR/gemini-global.md" << EOF
$MARKER
## Memory Vault Integration

This machine runs a cross-tool memory synchronization system (memory-vault).

What you should know:
- Your memories (## Gemini Added Memories) are synced every 30 minutes
- Cross-tool knowledge from Claude/Antigravity/OpenClaw/Codex appears in
  the "## Cross-Tool Context" section (auto-synced, do not edit that section)
- Your conversation history is archived before the 30-day auto-cleanup

Best practices:
- Use save_memory for important decisions — they will be synced cross-tool
- The "## Cross-Tool Context" section is auto-managed, do not edit it manually
$MARKER
EOF
echo "  gemini-global.md ✓"

# ── Gemini CLI 项目级 ──
cat > "$TEMPLATES_DIR/gemini-project.md" << EOF
$MARKER
## Cross-Tool Integration

This project uses memory-vault for cross-tool knowledge sharing with Claude, OpenClaw, Codex.
Cross-tool context is auto-synced — check ~/.gemini/GEMINI.md for details.
$MARKER
EOF
echo "  gemini-project.md ✓"

# ── OpenClaw MEMORY.md ──
cat > "$TEMPLATES_DIR/openclaw-memory.md" << EOF
$MARKER
## Memory Vault Integration

This machine runs memory-vault for cross-tool memory synchronization.

- Daily notes (memory/*.md) are archived and distilled automatically
- Cross-tool knowledge from Claude/Gemini/Antigravity/Codex appears in
  the "## Cross-Tool Knowledge" section (auto-synced, do not edit)
- MEMORY.md, SOUL.md, HEARTBEAT.md, USER.md are synced across machines

Best practices:
- Write important discoveries to MEMORY.md — they will be shared cross-tool
- The "## Cross-Tool Knowledge" section is auto-managed
$MARKER
EOF
echo "  openclaw-memory.md ✓"

# ── OpenClaw SOUL.md (不覆盖，仅提供参考模板) ──
cat > "$TEMPLATES_DIR/openclaw-soul.md" << EOF
$MARKER
## Cross-Machine Sync

This SOUL.md is synced across machines via memory-vault sync-config module.
Edits on any machine will be collected and available for reference on others.
$MARKER
EOF
echo "  openclaw-soul.md ✓"

# ── OpenClaw USER.md ──
cat > "$TEMPLATES_DIR/openclaw-user.md" << EOF
$MARKER
## Cross-Machine Sync

This USER.md is synced across machines via memory-vault.
$MARKER
EOF
echo "  openclaw-user.md ✓"

# ── Codex CLI ──
cat > "$TEMPLATES_DIR/codex-global.md" << EOF
$MARKER
## Memory Vault Integration

This machine uses memory-vault for cross-tool memory synchronization.

- AGENTS.md content is synced every 30 minutes
- Cross-tool knowledge from Claude/Gemini/Antigravity/OpenClaw appears in
  the "## Cross-Tool Context" section (auto-synced, do not edit)

Best practices:
- Write important decisions in this file — they will be shared cross-tool
- The "## Cross-Tool Context" section is auto-managed
$MARKER
EOF
echo "  codex-global.md ✓"

echo ""
echo "=== 模板初始化完成 ==="
echo ""
echo "文件位置: $TEMPLATES_DIR/"
ls "$TEMPLATES_DIR/"
echo ""
echo "下一步:"
echo "  1. 编辑模板内容 (按你的需求调整)"
echo "  2. 提交并推送:"
echo "     cd $VAULT_ROOT"
echo "     jj describe -m 'init: config templates'"
echo "     jj new && jj git push --allow-new"
echo "  3. 其他机器 harvest 时会自动注入这些模板"
echo ""
echo "模板中的 '$MARKER' 标记用于幂等更新:"
echo "  - 首次注入: 追加到文件末尾"
echo "  - 后续更新: 只替换标记之间的内容"
echo "  - 不会重复注入，不会破坏用户手写内容"
