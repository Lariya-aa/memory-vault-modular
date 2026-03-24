#!/bin/bash
# setup.sh — 模块化版本一键初始化
set -euo pipefail

GITLAB_URL="${1:?Usage: ./setup.sh <gitlab-ssh-url>}"
VAULT="${MEMORY_VAULT:-$HOME/memory-vault}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Memory Vault Modular Setup ==="
echo "GitLab: $GITLAB_URL"
echo "Vault:  $VAULT"

# 1. 安装 jj
if ! command -v jj &>/dev/null; then
  if [[ "$(uname)" == "Darwin" ]]; then brew install jj; else curl -fsSL https://jj-vcs.github.io/jj/install.sh | bash; fi
fi
echo "jj: $(jj --version)"

# 2. 配置 jj
MACHINE=$(hostname -s)
jj config set --user user.name "memory-vault@$MACHINE"
jj config set --user user.email "memory-vault@$MACHINE.local"

# 3. 克隆或初始化
if [ -d "$VAULT/.jj" ]; then
  echo "Vault exists at $VAULT"
  cd "$VAULT"
  jj git fetch --all-remotes 2>/dev/null || true
else
  if git ls-remote "$GITLAB_URL" &>/dev/null 2>&1; then
    jj git clone --colocate "$GITLAB_URL" "$VAULT"
    cd "$VAULT"
  else
    mkdir -p "$VAULT" && cd "$VAULT"
    jj git init --colocate
    jj git remote add origin "$GITLAB_URL"
    jj describe -m "init: memory-vault modular

[metadata]
type: init
machine: $MACHINE"
    jj new
    echo "Create repo on GitLab first, then: cd $VAULT && jj git push --allow-new"
  fi
fi

# 4. 拷贝项目文件到 vault
cp -r "$PROJECT_ROOT/core" "$VAULT/"
cp -r "$PROJECT_ROOT/modules" "$VAULT/"
cp -r "$PROJECT_ROOT/config" "$VAULT/"
cp "$PROJECT_ROOT/.gitlab-ci.yml" "$VAULT/" 2>/dev/null || true
cp "$PROJECT_ROOT/.gitignore" "$VAULT/" 2>/dev/null || true
chmod +x "$VAULT/core/"*.sh "$VAULT/modules/"*/run.sh 2>/dev/null || true
echo "Files installed"

# 5. 定时任务
if [[ "$(uname)" == "Darwin" ]]; then
  PLIST_SRC="$PROJECT_ROOT/launchd/com.user.memory-harvest.plist"
  PLIST_DST="$HOME/Library/LaunchAgents/com.user.memory-harvest.plist"
  if [ -f "$PLIST_SRC" ]; then
    sed -e "s|/Users/yaya|$HOME|g" -e "s|/Users/yaya/memory-vault|$VAULT|g" "$PLIST_SRC" > "$PLIST_DST"
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    launchctl load "$PLIST_DST"
    echo "launchd: 30min ✓"
  fi
else
  CRON_LINE="*/30 * * * * MEMORY_VAULT=$VAULT PATH=/usr/local/bin:\$PATH /bin/bash $VAULT/modules/harvest/run.sh >> /tmp/memory-harvest.log 2>&1"
  (crontab -l 2>/dev/null | grep -v "memory-harvest"; echo "$CRON_LINE") | crontab -
  echo "cron: 30min ✓"
fi

# 6. 注册项目 + 首次收割
export MEMORY_VAULT="$VAULT" VAULT_ROOT="$VAULT" MODULE_DIR="$VAULT/modules/harvest"
bash "$VAULT/core/project-register.sh"
bash "$VAULT/modules/harvest/run.sh"

echo ""
echo "=== Done ==="
echo "  Vault:   $VAULT"
echo "  Machine: $MACHINE"
echo ""
echo "  模块管理: source $VAULT/core/module-loader.sh && list_modules"
echo "  手动管线: source $VAULT/core/module-loader.sh && run_pipeline"
echo "  管理工具: VAULT_ROOT=$VAULT bash $VAULT/modules/admin/run.sh status"
