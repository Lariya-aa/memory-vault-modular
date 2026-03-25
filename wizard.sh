#!/bin/bash
# wizard.sh — Memory Vault 交互式安装向导
#
# 自动检测是首台机器还是后续机器，引导用户完成全部配置。
# 运行完毕后，系统即可开始工作。
#
# 用法:
#   bash wizard.sh
#
set -euo pipefail

# ── 颜色 ──
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

step_num=0
step() {
  step_num=$((step_num + 1))
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Step $step_num: $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
error()   { echo -e "  ${RED}✗${NC} $1"; }
ask()     { echo -e "  ${CYAN}?${NC} $1"; }
waiting() { echo -e "  ${YELLOW}…${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 找到项目根目录 (wizard.sh 可能在 core/ 下)
if [ -f "$SCRIPT_DIR/module-loader.sh" ]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -f "$SCRIPT_DIR/core/module-loader.sh" ]; then
  PROJECT_ROOT="$SCRIPT_DIR"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

VAULT="${MEMORY_VAULT:-$HOME/memory-vault}"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Memory Vault — 交互式安装向导            ║${NC}"
echo -e "${BOLD}║     跨网络多工具 AI Agent 记忆蒸馏系统       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════
# 检测环境
# ═══════════════════════════════════════════════
PLATFORM="unknown"
MACHINE=$(hostname -s)
if [[ "$(uname)" == "Darwin" ]]; then
  PLATFORM="mac"
  MACHINE_DESC="Mac ($MACHINE)"
elif command -v termux-info &>/dev/null 2>&1; then
  PLATFORM="termux"
  MACHINE="android-$(getprop ro.product.model 2>/dev/null | tr ' ' '-' || echo 'phone')"
  MACHINE_DESC="Android Termux ($MACHINE)"
elif [[ "$(uname)" == "Linux" ]]; then
  PLATFORM="linux"
  MACHINE_DESC="Linux ($MACHINE)"
else
  PLATFORM="other"
  MACHINE_DESC="$MACHINE"
fi

echo -e "  平台: ${BOLD}$MACHINE_DESC${NC}"
echo -e "  Vault 路径: ${BOLD}$VAULT${NC}"
echo ""

# ═══════════════════════════════════════════════
# 模式选择
# ═══════════════════════════════════════════════

echo -e "  请选择操作模式:"
echo -e "  [1] ${CYAN}全新安装 / 完整修复 (Deploy & Repair)${NC}  - 初始化核心并在当前环境部署所有依赖"
echo -e "  [2] ${GREEN}仅同步更新代码 (Source Code Sync)${NC}      - 仅将模块代码增量同步到私有 Vault (不改配置)"
echo -e "  [3] ${YELLOW}本地跑满蒸馏管线 (Local Pipeline Run)${NC} - 绕过 CI 限制，本机极速执行 L0-L3 全流程"
echo -e "  [4] ${BOLD}纯本地挂机模式 (Local Daemon Mode)${NC}   - 彻底无需云端跑管线，本机每 30分钟隐身常驻提纯"
echo ""
read -p "  [1/2/3/4] (默认 1): " run_mode
run_mode=${run_mode:-1}

if [ "$run_mode" = "2" ]; then
  echo ""
  step "执行代码同步"
  if [ "$PROJECT_ROOT" = "$VAULT" ]; then
    error "当前目录已经是部署后的私有 Vault。请只在源码仓 (模块化) 目录执行此操作。"
    exit 1
  fi
  
  if [ ! -d "$VAULT" ]; then
    error "未检测到已部署的私有 Vault ($VAULT)。请先使用模式 [1] 进行完整安装。"
    exit 1
  fi
  
  waiting "正在把最新核心模块刷入 $VAULT ..."
  
  # 精确的增量同步 (只同步核心逻辑，跳过个人配置和记录)
  mkdir -p "$VAULT/modules" "$VAULT/core"
  rsync -av --delete --exclude='*.json' --exclude='*.example.*' --exclude='.git*' --exclude='.DS_Store' "$PROJECT_ROOT/modules/" "$VAULT/modules/" > /dev/null
  rsync -av --delete --exclude='.git*' "$PROJECT_ROOT/core/" "$VAULT/core/" > /dev/null
  
  # 附带同步管控向导与全部大本营文档
  cp "$PROJECT_ROOT/wizard.sh" "$VAULT/" 2>/dev/null || true
  cp "$PROJECT_ROOT/"*.md "$VAULT/" 2>/dev/null || true
  cp -r "$PROJECT_ROOT/launchd" "$VAULT/" 2>/dev/null || true
  chmod +x "$VAULT/wizard.sh" 2>/dev/null || true
  
  info "核心模块及全局文档同步完成！您的私有数据与 JSON 配置绝对安全。"
  exit 0
fi

if [ "$run_mode" = "3" ]; then
  echo ""
  step "本地极速执行 L0-L3 蒸馏全流程"
  
  if [ ! -f "$VAULT/core/module-loader.sh" ]; then
    error "未检测到核心运行库 ($VAULT)。请先使用模式 [1] 初始化系统。"
    exit 1
  fi
  
  echo "  该模式将利用您本机的极速网络和算力直接跑完长达千字的初次记忆合并，"
  echo "  完美绕过基于免费 CI 运行平台长达 60 分钟强制断网的 Timeout 限制。"
  echo ""
  waiting "即将按序挂载运行管线..."
  echo ""
  
  export MEMORY_VAULT="$VAULT"
  # 必须使用 bash subshell 或由 source 引发
  source "$VAULT/core/module-loader.sh"
  
  echo -e "  ${CYAN}[1/7] 归档收集 (Harvest)${NC}"
  run_module harvest
  
  echo -e "  ${CYAN}[2/7] L0 原始对话记忆提取 (Extract & Distill)${NC}"
  run_module distill-l0
  
  echo -e "  ${CYAN}[3/7] L1 死数据去重去脏 (Dedup)${NC}"
  run_module distill-l1
  
  echo -e "  ${CYAN}[4/7] L1.5 语义智能漂移分类 (Classify)${NC}"
  run_module classify
  
  echo -e "  ${CYAN}[5/7] L2 跨端大模型语义合并 (Semantic Merge)${NC}"
  run_module distill-l2
  
  echo -e "  ${CYAN}[6/7] L3 最终知识树提纯 (Global Refinement)${NC}"
  run_module distill-l3
  
  echo -e "  ${CYAN}[7/7] Writeback 工具态回写装箱 (Writeback)${NC}"
  run_module writeback
  
  echo ""
  info "本地首航全管线执行完毕！您的所有 AI 记忆现在已经高压浓缩成了最纯粹的 Markdown 晶体并被 JJ PUSH 推送成功。"
  exit 0
fi

# ═══════════════════════════════════════════════
step "检查依赖"
# ═══════════════════════════════════════════════

MISSING=""

# git
if command -v git &>/dev/null; then
  info "git: $(git --version | head -1)"
else
  error "git: 未安装"
  MISSING="$MISSING git"
fi

# jj
if command -v jj &>/dev/null; then
  info "jj: $(jj --version)"
else
  warn "jj: 未安装"
  echo ""
  ask "是否现在安装 jj?"
  read -p "  [Y/n] " install_jj
  if [ "${install_jj:-Y}" != "n" ] && [ "${install_jj:-Y}" != "N" ]; then
    case "$PLATFORM" in
      mac)    brew install jj ;;
      termux) pkg install -y rust && cargo install --locked --bin jj jj-cli ;;
      linux)  curl -fsSL https://jj-vcs.github.io/jj/install.sh | bash ;;
    esac
    if command -v jj &>/dev/null; then
      info "jj: $(jj --version) — 安装成功"
    else
      warn "jj 安装失败, 将使用 git 兼容模式 (功能受限)"
    fi
  fi
fi

# python3
if command -v python3 &>/dev/null; then
  info "python3: $(python3 --version)"
else
  error "python3: 未安装"
  MISSING="$MISSING python3"
fi

# node (Gemini CLI 需要)
if command -v node &>/dev/null; then
  info "node: $(node --version)"
else
  warn "node: 未安装 (Gemini CLI 需要)"
fi

if [ -n "$MISSING" ]; then
  echo ""
  error "缺少必要依赖:$MISSING"
  echo "  请先安装后重新运行此脚本"
  exit 1
fi

# ═══════════════════════════════════════════════
step "配置 GitLab 连接"
# ═══════════════════════════════════════════════

GITLAB_URL=""
if [ -d "$VAULT/.jj" ] || [ -d "$VAULT/.git" ]; then
  # 已有 vault, 读取 remote
  GITLAB_URL=$(cd "$VAULT" && git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$GITLAB_URL" ]; then
    info "已有 Vault, GitLab: $GITLAB_URL"
  fi
fi

if [ -z "$GITLAB_URL" ]; then
  echo "  请输入 GitLab 仓库的 SSH 地址"
  echo "  例: git@gitlab.your-ddns.com:user/memory-vault.git"
  echo ""
  read -p "  GitLab SSH URL: " GITLAB_URL

  if [ -z "$GITLAB_URL" ]; then
    error "GitLab URL 不能为空"
    exit 1
  fi
fi

# 测试 SSH 连接 (仅针对远端地址)
if [[ "$GITLAB_URL" == *"@"* ]]; then
  echo ""
  waiting "测试 SSH 连接..."
  HOST=$(echo "$GITLAB_URL" | sed 's/.*@//' | sed 's/:.*//')
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -T "git@$HOST" 2>&1 | grep -qi "welcome\|success\|authenticated"; then
    info "SSH 连接: $HOST ✓"
  else
    # SSH key 可能不存在
    if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
      warn "未找到 SSH Key"
      ask "是否生成新的 SSH Key?"
      read -p "  [Y/n] " gen_key
      if [ "${gen_key:-Y}" != "n" ] && [ "${gen_key:-Y}" != "N" ]; then
        ssh-keygen -t ed25519 -C "memory-vault@$MACHINE" -f "$HOME/.ssh/id_ed25519" -N ""
        echo ""
        echo -e "  ${YELLOW}请将以下公钥添加到远端主机:${NC}"
        echo ""
        echo "  ┌─────────────────────────────────────────────────┐"
        cat "$HOME/.ssh/id_ed25519.pub" | sed 's/^/  │ /'
        echo "  └─────────────────────────────────────────────────┘"
        echo ""
        read -p "  添加完成后按 Enter 继续..."
      fi
    else
      warn "SSH 连接失败, 可能需要将公钥添加到远端"
      echo "  公钥: $(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || cat "$HOME/.ssh/id_rsa.pub" 2>/dev/null || echo '未找到')"
      read -p "  按 Enter 继续 (或 Ctrl+C 退出修复后重试)..."
    fi
  fi
else
  echo ""
  info "检测到局域网/共享映射本地路径作为版本中心: $GITLAB_URL"
  info "已为您自动跳过外网 SSH 测试 ✓"
fi

# ═══════════════════════════════════════════════
step "初始化 Vault 仓库"
# ═══════════════════════════════════════════════

IS_FIRST_MACHINE=false

if [ -d "$VAULT/.jj" ] || [ -d "$VAULT/.git" ]; then
  info "Vault 已存在: $VAULT"
  cd "$VAULT"
  jj git fetch --all-remotes 2>/dev/null || git pull --rebase 2>/dev/null || true
else
  # 尝试 clone
  waiting "尝试从 GitLab 克隆..."
  if git ls-remote "$GITLAB_URL" &>/dev/null 2>&1; then
    if command -v jj &>/dev/null; then
      jj git clone --colocate "$GITLAB_URL" "$VAULT"
    else
      git clone "$GITLAB_URL" "$VAULT"
    fi
    info "克隆成功"
    cd "$VAULT"
  else
    warn "远端仓库不存在, 这是首台机器"
    IS_FIRST_MACHINE=true

    mkdir -p "$VAULT"
    cd "$VAULT"

    if command -v jj &>/dev/null; then
      jj git init --colocate
      jj git remote add origin "$GITLAB_URL"
    else
      git init
      git remote add origin "$GITLAB_URL"
    fi
    info "本地仓库初始化完成"
  fi
fi

# ═══════════════════════════════════════════════
step "安装项目文件"
# ═══════════════════════════════════════════════

# 如果是首台机器或 vault 中没有 core/, 从项目模板复制
if [ ! -f "$VAULT/core/module-loader.sh" ]; then
  if [ -f "$PROJECT_ROOT/core/module-loader.sh" ]; then
    cp -r "$PROJECT_ROOT/core" "$VAULT/"
    cp -r "$PROJECT_ROOT/modules" "$VAULT/"
    cp -r "$PROJECT_ROOT/config" "$VAULT/"
    cp "$PROJECT_ROOT/.gitlab-ci.yml" "$VAULT/" 2>/dev/null || true
    cp "$PROJECT_ROOT/.gitignore" "$VAULT/" 2>/dev/null || true
    cp -r "$PROJECT_ROOT/launchd" "$VAULT/" 2>/dev/null || true
    
    # 附带部署向导自身说明文档
    cp "$PROJECT_ROOT/wizard.sh" "$VAULT/" 2>/dev/null || true
    cp "$PROJECT_ROOT/"*.md "$VAULT/" 2>/dev/null || true
    
    chmod +x "$VAULT/core/"*.sh "$VAULT/modules/"*/run.sh 2>/dev/null || true
    chmod +x "$VAULT/modules/"*/*.sh 2>/dev/null || true
    info "项目文件已安装"
  else
    warn "未找到项目模板, 请确保 wizard.sh 在项目目录中运行"
  fi
else
  info "项目文件已存在"
fi

# ═══════════════════════════════════════════════
step "配置 jj"
# ═══════════════════════════════════════════════

if command -v jj &>/dev/null; then
  jj config set --user user.name "memory-vault@$MACHINE"
  jj config set --user user.email "memory-vault@$MACHINE.local"
  info "jj 用户: memory-vault@$MACHINE"
else
  info "跳过 (使用 git 模式)"
fi

# ═══════════════════════════════════════════════
step "注册本机项目"
# ═══════════════════════════════════════════════

echo "  project-register 会扫描本机的 git 项目,"
echo "  用 git remote URL 作为跨机器的唯一标识。"
echo ""

# 确认搜索路径
DEFAULT_ROOTS="$HOME/projects $HOME/Developer $HOME/code"
echo "  默认搜索路径: $DEFAULT_ROOTS"
ask "是否使用默认路径? 如需添加其他路径, 请输入 (空格分隔):"
read -p "  [Enter=默认] " custom_roots

SEARCH_ROOTS="${custom_roots:-$DEFAULT_ROOTS}"

if [ -f "$VAULT/core/project-register.sh" ]; then
  VAULT_ROOT="$VAULT" bash "$VAULT/core/project-register.sh" $SEARCH_ROOTS
else
  warn "project-register.sh 未找到, 跳过"
fi

# ═══════════════════════════════════════════════
# 首台机器: 初始化模板
# ═══════════════════════════════════════════════

if [ "$IS_FIRST_MACHINE" = true ] || [ ! -d "$VAULT/configs/_templates" ]; then
  step "初始化配置模板 (首台机器)"

  echo "  sync-config 模板定义了注入到各工具的集成说明。"
  echo "  初始化后你可以编辑它们, push 到 GitLab 后所有机器自动生效。"
  echo ""

  if [ -f "$VAULT/modules/sync-config/init-templates.sh" ]; then
    VAULT_ROOT="$VAULT" bash "$VAULT/modules/sync-config/init-templates.sh"
  else
    warn "init-templates.sh 未找到"
  fi

  echo ""
  ask "是否现在编辑模板? (可以之后再编辑)"
  read -p "  [y/N] " edit_templates
  if [ "$edit_templates" = "y" ] || [ "$edit_templates" = "Y" ]; then
    EDITOR="${EDITOR:-vim}"
    echo "  用 $EDITOR 打开模板目录..."
    echo "  编辑完成后保存退出即可"
    $EDITOR "$VAULT/configs/_templates/"
  fi
else
  step "同步配置模板"
  echo "  从 vault 中读取模板, 注入到本地各工具..."
  echo ""
fi

# 执行 sync-config: 分发模板 + 收集本地配置
if [ -f "$VAULT/modules/sync-config/run.sh" ]; then
  VAULT_ROOT="$VAULT" MODULE_DIR="$VAULT/modules/sync-config" \
    bash "$VAULT/modules/sync-config/run.sh"
fi

# ═══════════════════════════════════════════════
step "配置定时收割"
# ═══════════════════════════════════════════════

echo "  定时任务每 3 小时自动收割本机各工具的记忆和对话,"
echo "  同步到 vault 并推送到 GitLab。"
echo ""

case "$PLATFORM" in
  mac)
    PLIST_SRC="$VAULT/launchd/com.user.memory-harvest.plist"
    PLIST_DST="$HOME/Library/LaunchAgents/com.user.memory-harvest.plist"
    if [ -f "$PLIST_SRC" ]; then
      sed -e "s|/Users/yaya|$HOME|g" \
          -e "s|/Users/yaya/memory-vault|$VAULT|g" \
          "$PLIST_SRC" > "$PLIST_DST"
          
      if [ "$run_mode" = "4" ]; then
        # Mac 本机挂机模式：将原本默认指向 harvest 的节点暴力倒转到 local-daemon 全局调度室
        sed -i "" "s|modules/harvest/run.sh|modules/local-daemon/run.sh|g" "$PLIST_DST"
      fi

      launchctl unload "$PLIST_DST" 2>/dev/null || true
      launchctl load "$PLIST_DST"
      info "launchd: 每 3 小时 ✓"
    else
      warn "launchd plist 未找到, 需要手动配置"
    fi
    ;;
  linux)
    if [ "$run_mode" = "4" ]; then
      HARVEST_SCRIPT="$VAULT/modules/local-daemon/run.sh"
    else
      HARVEST_SCRIPT="$VAULT/modules/harvest/run.sh"
    fi
    CRON_LINE="0 */3 * * * MEMORY_VAULT=$VAULT VAULT_ROOT=$VAULT MODULE_DIR=\$(dirname \$HARVEST_SCRIPT) PATH=/usr/local/bin:\$PATH /bin/bash \$HARVEST_SCRIPT >> /tmp/memory-harvest.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "memory-harvest"; echo "$CRON_LINE") | crontab -
    info "cron: 每 3 小时 ✓"
    ;;
  termux)
    if command -v crond &>/dev/null || pkg install -y cronie 2>/dev/null; then
      if [ "$run_mode" = "4" ]; then
        HARVEST_SCRIPT="$VAULT/modules/local-daemon/run.sh"
      else
        HARVEST_SCRIPT="$VAULT/scripts/harvest-termux.sh"
        [ -f "$HARVEST_SCRIPT" ] || HARVEST_SCRIPT="$VAULT/modules/harvest/run.sh"
      fi
      CRON_LINE="0 */3 * * * MEMORY_VAULT=$VAULT VAULT_ROOT=$VAULT /bin/bash \$HARVEST_SCRIPT >> \$HOME/memory-harvest.log 2>&1"
      (crontab -l 2>/dev/null | grep -v "memory-harvest"; echo "$CRON_LINE") | crontab -
      crond 2>/dev/null || true
      info "cronie: 每 3 小时 ✓"
      warn "每次重启 Termux 后需运行: crond"
    else
      warn "cronie 安装失败, 需手动收割"
    fi
    ;;
esac

# ═══════════════════════════════════════════════
step "首次收割"
# ═══════════════════════════════════════════════

echo "  执行首次收割, 收集本机所有工具的记忆和对话..."
echo ""

export MEMORY_VAULT="$VAULT" VAULT_ROOT="$VAULT"
export MODULE_DIR="$VAULT/modules/harvest"

if [ -f "$VAULT/modules/harvest/run.sh" ]; then
  bash "$VAULT/modules/harvest/run.sh" || warn "收割遇到问题 (可能是部分工具未安装, 属正常)"
else
  warn "harvest/run.sh 未找到"
fi

# ═══════════════════════════════════════════════
step "推送到 GitLab"
# ═══════════════════════════════════════════════

if [ "$IS_FIRST_MACHINE" = true ]; then
  echo -e "  ${YELLOW}这是首台机器, 需要先在 GitLab 上创建空仓库:${NC}"
  echo ""
  echo "  1. 打开 GitLab Web UI"
  echo "  2. New Project → Create blank project"
  echo "  3. 名称: memory-vault"
  echo "  4. 不要勾选 Initialize with README"
  echo ""
  read -p "  创建完成后按 Enter 推送..."

  cd "$VAULT"
  if command -v jj &>/dev/null; then
    jj git push --allow-new && info "推送成功" || error "推送失败, 请检查 GitLab 仓库和 SSH"
  else
    git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || error "推送失败"
  fi
else
  cd "$VAULT"
  if command -v jj &>/dev/null; then
    jj git push --allow-new 2>/dev/null && info "推送成功" || info "无新内容需要推送"
  else
    git push 2>/dev/null && info "推送成功" || info "无新内容需要推送"
  fi
fi

# ═══════════════════════════════════════════════
# CI 提示 (仅首台机器)
# ═══════════════════════════════════════════════
if [ "$IS_FIRST_MACHINE" = true ]; then
  step "配置 GitLab CI (仅需一次)"

  echo "  蒸馏管线运行在 GitLab CI 上, 需要在 Web UI 中配置:"
  echo ""
  echo -e "  ${BOLD}1. Pipeline Schedule:${NC}"
  echo "     GitLab → memory-vault → Build → Pipeline schedules → New"
  echo "     描述: Daily Distillation"
  echo "     间隔: 0 3 * * *"
  echo ""
  echo -e "  ${BOLD}2. CI Variable:${NC}"
  echo "     GitLab → memory-vault → Settings → CI/CD → Variables → Add"
  echo "     Key:   GEMINI_AUTH_CONFIG"
  echo "     Value: (你的 Gemini 认证 JSON)"
  echo "     Masked: ✓"
  echo ""
  echo -e "  ${BOLD}3. Runner 标签:${NC}"
  echo "     确保 Ubuntu VM 的 Runner 标签包含: ubuntu-runner"
  echo ""
  read -p "  了解后按 Enter 完成..."
fi

# ═══════════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            安装完成!                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Vault:    $VAULT"
echo "  Machine:  $MACHINE ($PLATFORM)"
echo "  GitLab:   $GITLAB_URL"
echo "  Schedule: 每 3 小时自动收割"
echo ""

# 检测到哪些工具
echo "  检测到的工具:"
[ -d "$HOME/.claude" ]              && info "Claude CLI"    || echo "  · Claude CLI (未检测到)"
[ -f "$HOME/.gemini/GEMINI.md" ]    && info "Gemini CLI"    || echo "  · Gemini CLI (未检测到)"
[ -d "$HOME/.codex" ]               && info "Codex CLI"     || echo "  · Codex CLI (未检测到)"
[ -d "$HOME/.openclaw" ]            && info "OpenClaw"      || echo "  · OpenClaw (未检测到)"
find $SEARCH_ROOTS -path "*antigravity/brain" -type d 2>/dev/null | head -1 | grep -q . \
  && info "Antigravity" || echo "  · Antigravity (未检测到)"

echo ""
echo "  常用命令:"
echo "    手动收割:  VAULT_ROOT=$VAULT MODULE_DIR=$VAULT/modules/harvest bash $VAULT/modules/harvest/run.sh"
echo "    查看状态:  VAULT_ROOT=$VAULT bash $VAULT/modules/admin/run.sh status"
echo "    查看日志:  tail -20 /tmp/memory-harvest.log"
echo "    管理工具:  VAULT_ROOT=$VAULT bash $VAULT/modules/admin/run.sh help"
echo ""
if [ "$IS_FIRST_MACHINE" = true ]; then
  echo -e "  ${YELLOW}下一步: 在其他机器上运行此向导即可自动同步配置${NC}"
else
  echo -e "  ${GREEN}配置已从 vault 同步, 所有工具已就绪${NC}"
fi
echo ""
