#!/bin/bash
# harvest/run.sh — 收割本机 AI 工具记忆 + 分发回写 + 按项目归档
set -euo pipefail

source "$VAULT_ROOT/core/jj-utils.sh"

MACHINE=$(hostname -s)
DATE=$(date +%F)
TOOLS_CHANGED=""
FILE_COUNT=0
PROJECTS_FILE="$VAULT_ROOT/projects.json"
CONFIG_FILE="$VAULT_ROOT/config/machines.json"

cd "$VAULT_ROOT"

# 确保 .last-harvest 存在
[ -f "$VAULT_ROOT/.last-harvest" ] || touch -t 197001010000 "$VAULT_ROOT/.last-harvest"

# ── 注册本机项目 ──
bash "$VAULT_ROOT/core/project-register.sh"

# ── jj git fetch ──
jj git fetch --all-remotes 2>/dev/null || true

# ── 分发回写文件 ──
WRITEBACK="$VAULT_ROOT/writeback"

# 段落替换函数
replace_section() {
  local file="$1" header="$2"
  [ -f "$file" ] || return 0
  python3 -c "
import re, sys
text = open(sys.argv[1], 'r').read()
text = re.sub(re.escape(sys.argv[2]) + r'.*?(?=\n## |\Z)', '', text, flags=re.DOTALL)
open(sys.argv[1], 'w').write(text.rstrip() + '\n\n')
" "$file" "$header" 2>/dev/null || true
}

# 按项目回写 (读 projects.json 找本机路径)
python3 -c "
import json, os, shutil
from pathlib import Path

vault = Path('$VAULT_ROOT')
wb = vault / 'writeback'
pf = vault / 'projects.json'
machine = '$MACHINE'

if not wb.exists() or not pf.exists():
    exit(0)

projects = json.load(open(pf))

for proj_name in os.listdir(wb):
    proj_wb = wb / proj_name
    if not proj_wb.is_dir():
        continue

    # 查找本机的 Claude project dir
    proj = projects.get(proj_name, {})
    machine_info = proj.get('machines', {}).get(machine, {})
    claude_dir = machine_info.get('claude_project_dir', '')

    if not claude_dir:
        continue

    # Claude: 回写到 per-project memory
    claude_src = proj_wb / 'claude' / 'cross-tool-context.md'
    if claude_src.exists():
        claude_dst = Path.home() / '.claude' / 'projects' / claude_dir / 'memory'
        claude_dst.mkdir(parents=True, exist_ok=True)
        shutil.copy2(claude_src, claude_dst / 'cross_tool_context.md')
        print(f'[writeback] {proj_name} → Claude ({claude_dir})')

# 全局回写
global_wb = wb / '_global'
if global_wb.exists():
    claude_src = global_wb / 'claude' / 'cross-tool-context.md'
    if claude_src.exists():
        global_dst = Path.home() / '.claude' / 'memory'
        global_dst.mkdir(parents=True, exist_ok=True)
        shutil.copy2(claude_src, global_dst / 'cross_tool_context.md')
        print('[writeback] _global → Claude')
" 2>/dev/null || true

# Gemini 全局回写
if [ -f "$WRITEBACK/_global/gemini/cross-tool-section.md" ]; then
  GEMINI_MD="$HOME/.gemini/GEMINI.md"
  if [ -f "$GEMINI_MD" ]; then
    replace_section "$GEMINI_MD" "## Cross-Tool Context"
    cat "$WRITEBACK/_global/gemini/cross-tool-section.md" >> "$GEMINI_MD"
    echo "[writeback] _global → Gemini"
  fi
fi

# OpenClaw 全局回写
if [ -d "$HOME/.openclaw/workspace" ] && [ -f "$WRITEBACK/_global/openclaw/cross-tool-memory.md" ]; then
  OCMEM="$HOME/.openclaw/workspace/MEMORY.md"
  if [ -f "$OCMEM" ]; then
    replace_section "$OCMEM" "## Cross-Tool Knowledge"
    cat "$WRITEBACK/_global/openclaw/cross-tool-memory.md" >> "$OCMEM"
    echo "[writeback] _global → OpenClaw"
  fi
fi

# ── 收割记忆 ──

# Claude: 直接扫描 ~/.claude/projects/ 下所有目录 (不依赖 projects.json)
python3 -c "
import os, shutil
from pathlib import Path

vault = Path('$VAULT_ROOT')
machine = '$MACHINE'
date = '$DATE'
lh = vault / '.last-harvest'
lh_mtime = lh.stat().st_mtime if lh.exists() else 0

claude_projects = Path.home() / '.claude' / 'projects'
claude_global_mem = Path.home() / '.claude' / 'memory'
count_mem = 0
count_conv = 0

# 全局记忆 (~/.claude/memory/)
if claude_global_mem.exists():
    dst = vault / 'raw' / 'claude' / machine / '_global'
    dst.mkdir(parents=True, exist_ok=True)
    for f in claude_global_mem.glob('*.md'):
        if f.name != 'cross_tool_context.md':
            shutil.copy2(f, dst)
            count_mem += 1

# 按 project dir 扫描 (不依赖 projects.json)
if claude_projects.exists():
    for proj_dir in claude_projects.iterdir():
        if not proj_dir.is_dir():
            continue
        dir_name = proj_dir.name  # e.g. -Users-yaya or -Users-yaya-AI-local

        # 记忆
        mem_dir = proj_dir / 'memory'
        if mem_dir.exists():
            dst = vault / 'raw' / 'claude' / machine / dir_name
            dst.mkdir(parents=True, exist_ok=True)
            for f in mem_dir.glob('*.md'):
                if f.name != 'cross_tool_context.md':
                    shutil.copy2(f, dst)
                    count_mem += 1

        # 对话 (所有 .jsonl)
        conv_dst = vault / 'conversations' / 'claude' / machine / dir_name / date
        has_new = False
        for f in proj_dir.glob('*.jsonl'):
            if f.stat().st_mtime > lh_mtime:
                if not has_new:
                    conv_dst.mkdir(parents=True, exist_ok=True)
                    has_new = True
                shutil.copy2(f, conv_dst)
                count_conv += 1

if count_mem > 0 or count_conv > 0:
    print(f'[harvest] Claude: {count_mem} memories, {count_conv} conversations')
" 2>/dev/null
if [ $? -eq 0 ]; then
  TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}claude"
  FILE_COUNT=$((FILE_COUNT + $(find raw/claude 2>/dev/null -type f | wc -l)))
fi

# Gemini: 全局记忆 + 所有对话 (不依赖 projects.json)
if [ -f "$HOME/.gemini/GEMINI.md" ]; then
  mkdir -p "raw/gemini/$MACHINE/_global"
  cp "$HOME/.gemini/GEMINI.md" "raw/gemini/$MACHINE/_global/"
  TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}gemini"
  FILE_COUNT=$((FILE_COUNT + 1))
  echo "[harvest] Gemini global memory"

  # 收割所有对话 (按 tmp 子目录归档，不做项目映射)
  python3 -c "
import os, shutil
from pathlib import Path

vault = Path('$VAULT_ROOT')
machine = '$MACHINE'
date = '$DATE'
gemini_tmp = Path.home() / '.gemini' / 'tmp'
lh = vault / '.last-harvest'
lh_mtime = lh.stat().st_mtime if lh.exists() else 0
count = 0

if not gemini_tmp.exists():
    exit(0)

for hash_dir in gemini_tmp.iterdir():
    chats = hash_dir / 'chats'
    if not chats.exists():
        continue

    # 用目录名作标识 (后续 L1.5 按内容分类)
    dst = vault / 'conversations' / 'gemini' / machine / '_global' / date
    for f in chats.glob('*.json'):
        if f.stat().st_mtime > lh_mtime:
            dst.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, dst)
            count += 1

if count > 0:
    print(f'[harvest] Gemini: {count} conversations')
" 2>/dev/null || true
fi

# Antigravity — 全局数据 (~/.gemini/antigravity/)
ANTI_GLOBAL="$HOME/.gemini/antigravity"
if [ -d "$ANTI_GLOBAL" ]; then
  ANTI_COUNT=0

  # brain 文档 (task.md, implementation_plan.md, walkthrough.md 等)
  if [ -d "$ANTI_GLOBAL/brain" ]; then
    for conv_dir in "$ANTI_GLOBAL/brain"/*/; do
      [ -d "$conv_dir" ] || continue
      conv_id=$(basename "$conv_dir")
      dst="raw/antigravity/$MACHINE/_global/brain/$conv_id"
      # 只复制比 .last-harvest 更新的 markdown 和 json
      new_files=$(find "$conv_dir" -maxdepth 1 \( -name '*.md' -o -name '*.json' \) \
        -newer "$VAULT_ROOT/.last-harvest" 2>/dev/null | head -20)
      if [ -n "$new_files" ]; then
        mkdir -p "$dst"
        echo "$new_files" | while read -r f; do cp "$f" "$dst/" 2>/dev/null; done
        ANTI_COUNT=$((ANTI_COUNT + $(echo "$new_files" | wc -l)))
      fi
    done
  fi

  # knowledge 知识库 (metadata.json + artifacts/*.md)
  if [ -d "$ANTI_GLOBAL/knowledge" ]; then
    mkdir -p "raw/antigravity/$MACHINE/_global/knowledge"
    rsync -a --include='*/' --include='*.md' --include='*.json' \
      --exclude='*.lock' --exclude='*' \
      "$ANTI_GLOBAL/knowledge/" "raw/antigravity/$MACHINE/_global/knowledge/"
    KI_COUNT=$(find "raw/antigravity/$MACHINE/_global/knowledge" -type f 2>/dev/null | wc -l | tr -d ' ')
    ANTI_COUNT=$((ANTI_COUNT + KI_COUNT))
  fi

  # conversations 目录中的 .pb 文件列表 (仅记录文件名和大小,不复制二进制)
  if [ -d "$ANTI_GLOBAL/conversations" ]; then
    mkdir -p "raw/antigravity/$MACHINE/_global/conversations"
    ls -lhS "$ANTI_GLOBAL/conversations/"*.pb 2>/dev/null | \
      awk '{print $5, $NF}' > "raw/antigravity/$MACHINE/_global/conversations/_index.txt" 2>/dev/null || true
  fi

  if [ "$ANTI_COUNT" -gt 0 ]; then
    TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}antigravity"
    FILE_COUNT=$((FILE_COUNT + ANTI_COUNT))
    echo "[harvest] Antigravity global: $ANTI_COUNT files (brain + knowledge)"
  fi
fi

# Antigravity — 项目级 (per-project brain)
ANTI_ROOTS=$(python3 -c "
import json, os
cfg = json.load(open('$VAULT_ROOT/config/machines.json')) if os.path.exists('$VAULT_ROOT/config/machines.json') else {}
roots = cfg.get('defaults', {}).get('antigravity_roots', ['~/projects', '~/Developer', '~/code'])
print(' '.join(os.path.expanduser(r) for r in roots))
" 2>/dev/null || echo "$HOME/projects $HOME/Developer $HOME/code")

for root_dir in $ANTI_ROOTS; do
  for brain in "$root_dir"/*/.gemini/antigravity/brain; do
    if [ -d "$brain" ]; then
      proj=$(basename "$(dirname "$(dirname "$(dirname "$brain")")")")
      mkdir -p "raw/antigravity/$MACHINE/$proj"
      rsync -a "$brain/" "raw/antigravity/$MACHINE/$proj/"
      TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}antigravity"
      FILE_COUNT=$((FILE_COUNT + $(find "$brain" -type f | wc -l)))
    fi
  done
done

# OpenClaw (全局)
if [ -d "$HOME/.openclaw/workspace" ]; then
  mkdir -p "raw/openclaw/$MACHINE/_global" "raw/openclaw/$MACHINE/_global/daily"
  cp "$HOME/.openclaw/workspace/MEMORY.md" "raw/openclaw/$MACHINE/_global/" 2>/dev/null || true
  rsync -a "$HOME/.openclaw/workspace/memory/" "raw/openclaw/$MACHINE/_global/daily/" 2>/dev/null || true
  TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}openclaw"
  echo "[harvest] OpenClaw memory"
fi

# Codex (全局 + per-project)
if [ -f "$HOME/.codex/AGENTS.md" ]; then
  mkdir -p "raw/codex/$MACHINE/_global"
  cp "$HOME/.codex/AGENTS.md" "raw/codex/$MACHINE/_global/"
  TOOLS_CHANGED="${TOOLS_CHANGED:+$TOOLS_CHANGED,}codex"
  FILE_COUNT=$((FILE_COUNT + 1))
  echo "[harvest] Codex AGENTS.md"
fi

# ── jj 提交 ──
touch "$VAULT_ROOT/.last-harvest"

if jj_has_changes; then
  jj_describe_harvest "$MACHINE" "$TOOLS_CHANGED" "$FILE_COUNT"
  CHANGE_ID=$(jj_change_id "@")
  echo "{\"change_id\":\"$CHANGE_ID\",\"machine\":\"$MACHINE\",\"tools\":\"$TOOLS_CHANGED\",\"files\":$FILE_COUNT,\"time\":\"$(date -Iseconds)\"}" \
    >> "$VAULT_ROOT/.harvest-log.jsonl"
  jj new
  jj_push
  echo "[harvest] Pushed $CHANGE_ID ($TOOLS_CHANGED, $FILE_COUNT files)"
else
  echo "[harvest] No changes"
fi
