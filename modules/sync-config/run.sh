#!/bin/bash
# sync-config/run.sh — 同步工具定义/配置文件
#
# 两个阶段:
#   1. distribute: vault/configs/_templates/ → 注入到本地各工具 (vault → 本地)
#   2. collect:    本地工具定义文件 → vault/configs/{tool}/{machine}/ (本地 → vault)
#
# 配置一次的流程:
#   Mac A: bash init-templates.sh → 编辑 configs/_templates/ → push
#   其他机器: harvest pull → sync-config 自动注入
#
set -euo pipefail

source "$VAULT_ROOT/core/jj-utils.sh"

MACHINE=$(hostname -s)
CONFIGS_DIR="$VAULT_ROOT/configs"
TEMPLATES_DIR="$CONFIGS_DIR/_templates"
MARKER="<!-- memory-vault-managed -->"

echo "=== Sync Config ==="

# ═══════════════════════════════════════════════
# 阶段 1: DISTRIBUTE — 模板 → 本地工具
# ═══════════════════════════════════════════════
echo "--- Phase 1: Distribute templates ---"

# 幂等注入函数: 检查标记，避免重复
inject_section() {
  local target="$1"     # 目标文件
  local template="$2"   # 模板文件
  local create="${3:-false}"  # 文件不存在时是否创建

  if [ ! -f "$template" ]; then
    return 0
  fi

  # 目标不存在: 如果允许创建，用模板初始化
  if [ ! -f "$target" ]; then
    if [ "$create" = "true" ]; then
      mkdir -p "$(dirname "$target")"
      cp "$template" "$target"
      echo "[distribute] Created: $target"
    fi
    return 0
  fi

  # 已有标记: 替换旧内容
  if grep -q "$MARKER" "$target" 2>/dev/null; then
    python3 -c "
import sys
marker = '$MARKER'
target = sys.argv[1]
template = open(sys.argv[2]).read().strip()

text = open(target).read()
# 找到 marker 之间的内容替换
start = text.find(marker)
end = text.find(marker, start + len(marker))
if start >= 0 and end > start:
    text = text[:start] + template + '\n' + text[end + len(marker):]
elif start >= 0:
    text = text[:start] + template + '\n'
open(target, 'w').write(text)
" "$target" "$template"
    echo "[distribute] Updated: $(basename "$target")"
    return 0
  fi

  # 无标记: 追加
  echo "" >> "$target"
  cat "$template" >> "$target"
  echo "[distribute] Injected: $(basename "$target")"
}

# Claude CLI — 全局 CLAUDE.md
if [ -f "$TEMPLATES_DIR/claude-global.md" ]; then
  inject_section "$HOME/.claude/CLAUDE.md" "$TEMPLATES_DIR/claude-global.md" true
fi

# Claude CLI — 按项目 CLAUDE.md
if [ -f "$TEMPLATES_DIR/claude-project.md" ] && [ -f "$VAULT_ROOT/projects.json" ]; then
  python3 -c "
import json, os
from pathlib import Path
projects = json.load(open('$VAULT_ROOT/projects.json'))
machine = '$MACHINE'
for proj_name, proj in projects.items():
    if proj_name == '_global': continue
    info = proj.get('machines', {}).get(machine, {})
    path = info.get('path', '')
    if path and os.path.isdir(path):
        print(path)
" 2>/dev/null | while read -r proj_path; do
    inject_section "$proj_path/CLAUDE.md" "$TEMPLATES_DIR/claude-project.md" false
  done
fi

# Gemini CLI — 全局 GEMINI.md
if [ -f "$TEMPLATES_DIR/gemini-global.md" ]; then
  inject_section "$HOME/.gemini/GEMINI.md" "$TEMPLATES_DIR/gemini-global.md" true
fi

# Gemini CLI — 按项目 GEMINI.md
if [ -f "$TEMPLATES_DIR/gemini-project.md" ] && [ -f "$VAULT_ROOT/projects.json" ]; then
  python3 -c "
import json, os
from pathlib import Path
projects = json.load(open('$VAULT_ROOT/projects.json'))
machine = '$MACHINE'
for proj_name, proj in projects.items():
    if proj_name == '_global': continue
    info = proj.get('machines', {}).get(machine, {})
    path = info.get('path', '')
    if path and os.path.isdir(path):
        print(path)
" 2>/dev/null | while read -r proj_path; do
    inject_section "$proj_path/GEMINI.md" "$TEMPLATES_DIR/gemini-project.md" false
  done
fi

# OpenClaw — MEMORY.md / SOUL.md / USER.md
for tmpl in openclaw-memory.md openclaw-soul.md openclaw-user.md; do
  if [ -f "$TEMPLATES_DIR/$tmpl" ] && [ -d "$HOME/.openclaw/workspace" ]; then
    # openclaw-memory.md → MEMORY.md
    target_name=$(echo "$tmpl" | sed 's/openclaw-//' | sed 's/\b\(.\)/\U\1/' | tr '[:lower:]' '[:upper:]' | sed 's/\.MD/.md/')
    # 简单映射
    case "$tmpl" in
      openclaw-memory.md)   inject_section "$HOME/.openclaw/workspace/MEMORY.md" "$TEMPLATES_DIR/$tmpl" false ;;
      openclaw-soul.md)     inject_section "$HOME/.openclaw/workspace/SOUL.md" "$TEMPLATES_DIR/$tmpl" false ;;
      openclaw-user.md)     inject_section "$HOME/.openclaw/workspace/USER.md" "$TEMPLATES_DIR/$tmpl" false ;;
    esac
  fi
done

# Codex CLI — AGENTS.md
if [ -f "$TEMPLATES_DIR/codex-global.md" ]; then
  inject_section "$HOME/.codex/AGENTS.md" "$TEMPLATES_DIR/codex-global.md" true
fi

# ═══════════════════════════════════════════════
# 阶段 2: COLLECT — 本地工具定义 → vault
# ═══════════════════════════════════════════════
echo "--- Phase 2: Collect configs ---"

# Claude 全局
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  DST="$CONFIGS_DIR/claude/$MACHINE"
  mkdir -p "$DST"
  cp "$HOME/.claude/CLAUDE.md" "$DST/CLAUDE.global.md"
  echo "[collect] Claude global CLAUDE.md"
fi

# Claude 按项目
if [ -f "$VAULT_ROOT/projects.json" ]; then
  python3 -c "
import json, shutil
from pathlib import Path
vault = Path('$VAULT_ROOT')
projects = json.load(open(vault / 'projects.json'))
for proj_name, proj in projects.items():
    if proj_name == '_global': continue
    info = proj.get('machines', {}).get('$MACHINE', {})
    path = info.get('path', '')
    if not path: continue
    f = Path(path) / 'CLAUDE.md'
    if f.exists():
        dst = vault / 'configs' / 'claude' / '$MACHINE' / f'CLAUDE.{proj_name}.md'
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dst)
        print(f'[collect] Claude CLAUDE.md → {proj_name}')
" 2>/dev/null || true
fi

# Gemini 全局 (只保留用户手写部分)
if [ -f "$HOME/.gemini/GEMINI.md" ]; then
  DST="$CONFIGS_DIR/gemini/$MACHINE"
  mkdir -p "$DST"
  python3 -c "
import re
text = open('$HOME/.gemini/GEMINI.md').read()
cleaned = re.sub(r'## Gemini Added Memories.*?(?=\n## |\Z)', '', text, flags=re.DOTALL)
cleaned = re.sub(r'## Cross-Tool Context.*?(?=\n## |\Z)', '', cleaned, flags=re.DOTALL)
open('$DST/GEMINI.user.md', 'w').write(cleaned.strip() + '\n')
" 2>/dev/null && echo "[collect] Gemini user GEMINI.md"
fi

# OpenClaw
if [ -d "$HOME/.openclaw/workspace" ]; then
  DST="$CONFIGS_DIR/openclaw/$MACHINE"
  mkdir -p "$DST"
  for f in SOUL.md HEARTBEAT.md USER.md; do
    [ -f "$HOME/.openclaw/workspace/$f" ] && cp "$HOME/.openclaw/workspace/$f" "$DST/"
  done
  echo "[collect] OpenClaw configs"
fi

# Codex
if [ -f "$HOME/.codex/AGENTS.md" ]; then
  DST="$CONFIGS_DIR/codex/$MACHINE"
  mkdir -p "$DST"
  cp "$HOME/.codex/AGENTS.md" "$DST/AGENTS.global.md"
  echo "[collect] Codex AGENTS.md"
fi

echo "[sync-config] Done for $MACHINE"
