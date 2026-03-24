#!/bin/bash
# termux-setup.sh — Termux (Android) 专用安装脚本
#
# 在 Termux 中运行:
#   pkg install git curl openssh python nodejs-lts
#   bash termux-setup.sh git@gitlab.your-ddns.com:user/memory-vault.git
#
set -euo pipefail

GITLAB_URL="${1:?用法: bash termux-setup.sh <gitlab-ssh-url>}"
VAULT="${MEMORY_VAULT:-$HOME/memory-vault}"
MACHINE="android-$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || echo 'phone')"

echo "=== Memory Vault Termux Setup ==="
echo "Machine: $MACHINE"
echo "GitLab:  $GITLAB_URL"
echo "Vault:   $VAULT"
echo ""

# ═══════════════════════════════════════════════
# 1. 安装依赖
# ═══════════════════════════════════════════════
echo "=== 安装依赖 ==="

# 基础工具
pkg install -y git openssh python nodejs-lts 2>/dev/null || true

# jj: 通过 cargo 编译 (Termux 无预编译包)
if ! command -v jj &>/dev/null; then
  echo "安装 jj (需要编译, 可能需要 10-20 分钟)..."
  echo "如果编译失败或太慢, 可以用 git 替代 (见脚本末尾说明)"

  if ! command -v cargo &>/dev/null; then
    pkg install -y rust
  fi

  # 编译 jj (只编译 CLI, 减少编译时间)
  cargo install --locked --bin jj jj-cli 2>&1 || {
    echo ""
    echo "⚠ jj 编译失败, 改用 git 兼容模式"
    echo "  后续命令用 git 代替 jj"
    USE_GIT_FALLBACK=1
  }
fi

if command -v jj &>/dev/null; then
  echo "jj: $(jj --version)"
  USE_GIT_FALLBACK=0
else
  USE_GIT_FALLBACK=1
fi

# Gemini CLI
if ! command -v gemini &>/dev/null; then
  npm install -g @google/gemini-cli
fi
echo "gemini: $(gemini --version 2>/dev/null || echo 'not installed')"

# ═══════════════════════════════════════════════
# 2. SSH Key (如果没有)
# ═══════════════════════════════════════════════
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  echo ""
  echo "=== 生成 SSH Key ==="
  ssh-keygen -t ed25519 -C "memory-vault@$MACHINE" -f "$HOME/.ssh/id_ed25519" -N ""
  echo ""
  echo "请把以下公钥添加到 GitLab:"
  echo "───────────────────────────────"
  cat "$HOME/.ssh/id_ed25519.pub"
  echo "───────────────────────────────"
  echo ""
  read -p "添加完成后按 Enter 继续..."
fi

# ═══════════════════════════════════════════════
# 3. 克隆/初始化 vault
# ═══════════════════════════════════════════════
if [ -d "$VAULT/.jj" ] || [ -d "$VAULT/.git" ]; then
  echo "Vault exists at $VAULT"
  cd "$VAULT"
else
  echo "=== 克隆 vault ==="
  if [ "$USE_GIT_FALLBACK" = "1" ]; then
    git clone "$GITLAB_URL" "$VAULT"
    cd "$VAULT"
  else
    jj git clone --colocate "$GITLAB_URL" "$VAULT"
    cd "$VAULT"
    jj config set --user user.name "memory-vault@$MACHINE"
    jj config set --user user.email "memory-vault@$MACHINE.local"
  fi
fi

# ═══════════════════════════════════════════════
# 4. 创建 Termux 专用收割脚本
# ═══════════════════════════════════════════════
cat > "$VAULT/scripts/harvest-termux.sh" << 'HARVEST_EOF'
#!/bin/bash
# harvest-termux.sh — Termux 精简版收割 (只收 Gemini CLI)
set -euo pipefail

VAULT="${MEMORY_VAULT:-$HOME/memory-vault}"
MACHINE="android-$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || echo 'phone')"
DATE=$(date +%F)

cd "$VAULT"

# 拉取最新
if command -v jj &>/dev/null; then
  jj git fetch --all-remotes 2>/dev/null || true
else
  git pull --rebase 2>/dev/null || true
fi

# ── 分发回写 ──
WRITEBACK="$VAULT/writeback"
if [ -f "$WRITEBACK/_global/gemini/cross-tool-section.md" ]; then
  GEMINI_MD="$HOME/.gemini/GEMINI.md"
  if [ -f "$GEMINI_MD" ]; then
    python3 -c "
import re
text = open('$GEMINI_MD', 'r').read()
text = re.sub(r'## Cross-Tool Context.*?(?=\n## |\Z)', '', text, flags=re.DOTALL)
open('$GEMINI_MD', 'w').write(text.rstrip() + '\n\n')
" 2>/dev/null || true
    cat "$WRITEBACK/_global/gemini/cross-tool-section.md" >> "$GEMINI_MD"
    echo "[writeback] Gemini updated"
  fi
fi

# ── 收割 Gemini CLI ──
TOOLS_CHANGED=""
FILE_COUNT=0

# Gemini 记忆
if [ -f "$HOME/.gemini/GEMINI.md" ]; then
  mkdir -p "raw/gemini/$MACHINE/_global"
  cp "$HOME/.gemini/GEMINI.md" "raw/gemini/$MACHINE/_global/"
  TOOLS_CHANGED="gemini"
  FILE_COUNT=$((FILE_COUNT + 1))
  echo "[harvest] Gemini memory"

  # 对话抢救
  for chatdir in "$HOME/.gemini/tmp"/*/chats; do
    if [ -d "$chatdir" ]; then
      mkdir -p "conversations/gemini/$MACHINE/_global/$DATE"
      find "$chatdir" -name "*.json" \
        -newer "$VAULT/.last-harvest" \
        -exec cp {} "conversations/gemini/$MACHINE/_global/$DATE/" \; 2>/dev/null || true
    fi
  done
  echo "[harvest] Gemini conversations"
fi

# ── 提交推送 ──
touch "$VAULT/.last-harvest"

if command -v jj &>/dev/null; then
  if jj diff --stat 2>/dev/null | grep -q '.'; then
    jj describe -m "harvest: $MACHINE $DATE $(date +%H:%M)

[metadata]
machine: $MACHINE
tools: $TOOLS_CHANGED
files_changed: $FILE_COUNT
type: harvest"
    jj new
    jj git push --allow-new
    echo "[harvest] Pushed via jj"
  else
    echo "[harvest] No changes"
  fi
else
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "harvest: $MACHINE $DATE $(date +%H:%M)"
    git push
    echo "[harvest] Pushed via git"
  else
    echo "[harvest] No changes"
  fi
fi
HARVEST_EOF

chmod +x "$VAULT/scripts/harvest-termux.sh"
echo "harvest-termux.sh created"

# ═══════════════════════════════════════════════
# 5. 配置定时任务
# ═══════════════════════════════════════════════
echo ""
echo "=== 配置定时任务 ==="

# 方法1: cronie (推荐)
if command -v crond &>/dev/null || pkg install -y cronie 2>/dev/null; then
  CRON_LINE="*/30 * * * * MEMORY_VAULT=$VAULT /bin/bash $VAULT/scripts/harvest-termux.sh >> $HOME/memory-harvest.log 2>&1"
  (crontab -l 2>/dev/null | grep -v "memory-harvest"; echo "$CRON_LINE") | crontab -

  # 确保 crond 运行
  crond 2>/dev/null || true

  echo "cron: 30min ✓"
  echo ""
  echo "注意: 每次重启 Termux 后需要手动启动 crond:"
  echo "  crond"
  echo ""
  echo "或者在 ~/.bashrc 中添加:"
  echo '  pgrep crond >/dev/null || crond'

else
  echo "cronie 安装失败, 使用手动方式"
  echo ""
  echo "每次打开 Termux 时手动运行:"
  echo "  bash ~/memory-vault/scripts/harvest-termux.sh"
fi

# 方法2: termux-job-scheduler (备选, 需要 Termux:API)
echo ""
echo "备选: 安装 Termux:API 实现后台定时"
echo "  pkg install termux-api"
echo '  termux-job-scheduler --job-id 1 --period-ms 1800000 --script "$HOME/memory-vault/scripts/harvest-termux.sh"'

# ═══════════════════════════════════════════════
# 6. 注册到 projects.json
# ═══════════════════════════════════════════════
echo ""
echo "=== 注册机器 ==="

python3 -c "
import json, os
from pathlib import Path

pf = Path('$VAULT/projects.json')
if not pf.exists():
    projects = {'_global': {'description': '跨项目全局记忆'}}
else:
    projects = json.load(open(pf))

g = projects.setdefault('_global', {'description': '跨项目全局记忆'})
machines = g.setdefault('machines', {})
machines['$MACHINE'] = {
    'path': '$HOME',
    'platform': 'android-termux',
}

json.dump(projects, open(pf, 'w'), ensure_ascii=False, indent=2)
print('Registered $MACHINE in projects.json')
"

# ═══════════════════════════════════════════════
# 7. 首次收割
# ═══════════════════════════════════════════════
echo ""
echo "=== 首次收割 ==="
bash "$VAULT/scripts/harvest-termux.sh"

# ═══════════════════════════════════════════════
# 8. 配置 GEMINI.md
# ═══════════════════════════════════════════════
GEMINI_MD="$HOME/.gemini/GEMINI.md"
if [ -f "$GEMINI_MD" ]; then
  if ! grep -q "Memory Vault" "$GEMINI_MD" 2>/dev/null; then
    cat >> "$GEMINI_MD" << 'GEMINI_EOF'

## Memory Vault Integration

This device (Android/Termux) runs memory-vault for cross-tool memory sync.
- Your memories are synced every 30 minutes (or on manual harvest)
- Cross-tool knowledge from Claude/Antigravity/OpenClaw/Codex on other machines
  appears in the "## Cross-Tool Context" section (auto-synced, do not edit)
- Conversations are archived before the 30-day auto-cleanup
GEMINI_EOF
    echo "[setup] GEMINI.md updated with vault integration"
  fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "  Vault:    $VAULT"
echo "  Machine:  $MACHINE"
echo "  jj:       $(jj --version 2>/dev/null || echo 'using git fallback')"
echo "  gemini:   $(gemini --version 2>/dev/null || echo 'not found')"
echo ""
echo "  手动收割: bash ~/memory-vault/scripts/harvest-termux.sh"
echo "  查看日志: cat ~/memory-harvest.log"
echo ""
if [ "$USE_GIT_FALLBACK" = "1" ]; then
  echo "  ⚠ jj 未安装, 使用 git 兼容模式"
  echo "    功能差异: 无 Change ID / 无 jj undo / push 冲突需手动 rebase"
  echo "    后续安装 jj: cargo install --locked --bin jj jj-cli"
fi
