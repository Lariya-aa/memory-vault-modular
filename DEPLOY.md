# Memory Vault 部署指南

## 目录

1. [前置条件](#前置条件)
2. [Mac 部署 (Claude CLI / Gemini CLI / Antigravity / Codex CLI)](#mac-部署)
3. [Ubuntu 部署 (GitLab CI/CD Runner)](#ubuntu-部署)
4. [Debian 部署 (OpenClaw)](#debian-部署)
5. [Android Termux 部署 (Gemini CLI)](#android-termux-部署)
6. [Windows 部署](#windows-部署)
7. [让各工具知道这个系统](#让各工具知道这个系统)
8. [验证部署](#验证部署)
9. [注意事项](#注意事项)

---

## 前置条件

| 条件 | 说明 |
|---|---|
| GitLab 仓库 | 在自托管 GitLab 上创建 `memory-vault` 空仓库 |
| SSH Key | 所有机器的 SSH 公钥添加到 GitLab |
| 网络打通 | 局域网2 通过 Snell+Surge / Lucky+DDNS 可访问局域网1 的 GitLab |
| jj ≥0.25 | 所有机器安装 jj |
| Gemini AI Pro | Mac 上 Gemini CLI 已登录 |

---

## 核心管控向导 (Wizard.sh)

Memory Vault 拥有一套极致解耦的全局控制终端 `wizard.sh`。不论网络环境和宿主机 OS 如何，您只需运行 `bash wizard.sh`，即可从以下 4 种底层控制流中自由切换：

| 选项 | 模式指令 | 适用场景与底层调度行为 |
|:---:|---|---|
| **[1]** | **全新安装 / 完整修复**<br>*(Deploy & Repair)* | **经典云端 CI 模式**。适用于初始化任何机器节点。向导会配置全局环境变量，并在系统级（launchd/cron）注入每 3 小时调用 `harvest` 的定时动作。机器只管收集发向远端，繁重的 LLM 提纯由 GitLab 云端计算。 |
| **[2]** | **仅同步更新代码**<br>*(Source Code Sync)* | **增量热更新**。当您在模块库开发了新的框架特性后选用此项。底层通过精密的 `rsync` 黑白名单，将核心逻辑直接刷入私有运行库，完美避开环境配置、个人 JSON 及记忆私有数据，防止错误覆写。 |
| **[3]** | **本地跑满蒸馏管线**<br>*(Local Pipeline Run)* | **单次破冰战**。由于各大 AI 原生工具累计的历史记录极度庞大，首次收割必然长达几千字。此模式强力接管本机全部算力连贯执行 L0~L3，绕过各类公用免费 CI 平台的 60分钟 Timeout 断网限制，极速完成首航结晶。 |
| **[4]** | **纯本地断网挂机版**<br>*(Local Daemon Mode)* | **无需任何云服务器的后台全自动引擎**。选定后，向导会将本机的长持定时任务改为指向 `local-daemon`。本地机器将变为兼具“收割器+蒸馏炉”的永动双核机器。每 3 小时触发基于 `flock` 文件锁防冲突的全景断网合并。 |

---

## 纯局域网 NAS 部署 (100% 离线特供)

如果您追求绝对的数据隐私且不想使用外网 GitLab，可以直接利用局域网内的 NAS 共享文件夹（SMB/NFS）作为版本交换中心。配合向导的 Option [4]，实现零断网风险、零公网痕迹的内网闭环大模型中枢：

1. **创建本地私有云原点 (Bare Repo)**
   在您的 NAS 共享网盘中，比如 Debian 的挂载点 `/mnt/nas/` 或 Windows 的映射盘 `Z:\`，直接初始化一个纯粹用作中转交换的空兵营仓库：
   `git init --bare /mnt/nas/memory-vault.git`

2. **指定核心算力机 (首选: Windows/Mac) → 选向导 [4]**
   找出网段中算力最好的一台机器担纲引擎计算与 LLM API 账单分发。运行向导 `bash wizard.sh` 并选择 `[4] 纯本地断网挂机版`。当要求填写 GitLab URL 时，**不需域名亦不需 SSH**，直接打入绝对路径：`file:///mnt/nas/memory-vault.git` 或者 `Z:/memory-vault.git`。向导会瞬间亮起绿灯自动跳过任何联网外呼校验。

3. **部署轻量级采集从节点 (如: 老旧 Debian / 安卓 Termux) → 选向导 [1]**
   其余所有的纯采集端无需配置引擎和 API Key。运行向导选择 `[1] 全新安装`，URL 同上填写内网 NAS 共享地址。这些影子兄弟只负责每 3 小时默默往内网 NAS 里投递本地的记忆碎块，核心机定点抓走后，再提领回完整的知识结晶反哺本体。

---

## Mac 部署

> 适用于: 两台 Mac (Claude CLI / Gemini CLI / Antigravity / Codex CLI)

### 1. 安装 jj

```bash
brew install jj
jj --version  # 确认 ≥0.25
```

### 2. 初始化 vault

```bash
# 克隆项目模板到本地 (首次)
cd ~/AI-local  # 或你存放项目的位置
# 假设你已经把 memory-vault-modular 推到了 GitLab

# 运行一键安装
bash memory-vault-modular/core/setup.sh git@gitlab.your-ddns.com:user/memory-vault.git
```

setup.sh 会自动:
- 配置 jj 用户信息 (`memory-vault@{hostname}`)
- clone 或 init 仓库到 `~/memory-vault`
- 注册本机所有 git 项目到 `projects.json`
- 安装 launchd 定时任务 (每3小时)
- 执行首次收割

### 3. 验证定时任务

```bash
# 查看 launchd 状态
launchctl list | grep memory-harvest

# 查看收割日志
tail -20 /tmp/memory-harvest.log

# 手动触发一次
MEMORY_VAULT=~/memory-vault VAULT_ROOT=~/memory-vault \
  MODULE_DIR=~/memory-vault/modules/harvest \
  bash ~/memory-vault/modules/harvest/run.sh
```

### 4. 配置 Gemini CLI 认证 (CI 用)

```bash
# 导出 Gemini 认证配置 (供 CI 使用)
cat ~/.config/gemini/config.json
# 把内容复制到 GitLab CI Variable:
# GitLab → memory-vault → Settings → CI/CD → Variables
# Key: GEMINI_AUTH_CONFIG
# Value: (粘贴上面的 JSON)
# Type: Variable, Protected: No, Masked: Yes
```

### 5. 确认工具路径

```bash
# 检查各工具目录是否存在
ls ~/.claude/memory/           # Claude 全局记忆
ls ~/.claude/projects/         # Claude 项目记忆
ls ~/.gemini/GEMINI.md         # Gemini 记忆
ls ~/.gemini/tmp/              # Gemini 对话
ls ~/.codex/                   # Codex (如果已安装)

# 检查 Antigravity brain 目录
# 需要确认你的项目实际在哪个目录下
find ~/projects ~/Developer ~/code -path "*/antigravity/brain" -type d 2>/dev/null

# 如果 Antigravity 项目不在默认路径, 修改配置:
# 编辑 ~/memory-vault/config/machines.json
# "antigravity_roots": ["~/your-actual-path"]
```

---

## Ubuntu 部署

> 适用于: ESXi 上的 Ubuntu VM (GitLab CI/CD Runner)

这台机器主要运行 CI pipeline, 不需要 harvest。

### 1. 安装 jj

```bash
curl -fsSL https://jj-vcs.github.io/jj/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
jj --version
```

### 2. 安装 Gemini CLI

```bash
# Node.js (如果没有)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
sudo apt-get install -y nodejs

# Gemini CLI
npm install -g @google/gemini-cli

# 验证
gemini --version
```

### 3. 确认 GitLab Runner

```bash
# Runner 已安装并注册 (你说已有)
sudo gitlab-runner verify

# 确认 Runner 标签包含 "ubuntu-runner"
sudo gitlab-runner list
# 如果标签不对, 重新注册或修改:
# sudo gitlab-runner register (选择 tags: ubuntu-runner)

# 或者修改 .gitlab-ci.yml 中的 tags 匹配你的 Runner 标签
```

### 4. 配置 CI Pipeline Schedule

```
在 GitLab Web UI 中:
memory-vault 仓库 → Build → Pipeline schedules → New schedule

描述: Daily Memory Distillation
间隔: 0 3 * * *    (每天凌晨3点, 或你喜欢的时间)
目标分支: main
激活: ✓
```

### 5. 配置 CI Variables

```
GitLab → memory-vault → Settings → CI/CD → Variables

添加:
  Key: GEMINI_AUTH_CONFIG
  Value: {"gemini_api_key": "..."}  (从 Mac 上复制)
  Masked: ✓
```

### 6. 测试 Pipeline

```bash
# 手动触发一次 pipeline 测试
# GitLab → memory-vault → Build → Pipelines → Run pipeline
# 或命令行:
cd /path/to/memory-vault
git push  # 如果有新提交, 或在 GitLab UI 手动触发
```

---

## Debian 部署

> 适用于: ESXi 上的 Debian VM (OpenClaw)

### 1. 安装 jj

```bash
curl -fsSL https://jj-vcs.github.io/jj/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
jj --version
```

### 2. 初始化 vault

```bash
# 克隆 vault
jj git clone --colocate git@gitlab.your-ddns.com:user/memory-vault.git ~/memory-vault
cd ~/memory-vault

# 拷贝模块文件 (如果还没有)
# 或者直接 clone 后已经有了

# 配置 jj
jj config set --user user.name "memory-vault@debian-vm"
jj config set --user user.email "memory-vault@debian-vm.local"
```

### 3. 配置 cron 定时收割

```bash
# 安装 cron (如果没有)
sudo apt-get install -y cron

# 设置定时任务
VAULT=~/memory-vault
(crontab -l 2>/dev/null | grep -v "memory-harvest"; \
 echo "0 */3 * * * MEMORY_VAULT=$VAULT VAULT_ROOT=$VAULT MODULE_DIR=$VAULT/modules/harvest PATH=/usr/local/bin:\$PATH /bin/bash $VAULT/modules/harvest/run.sh >> /tmp/memory-harvest.log 2>&1") | crontab -

# 验证
crontab -l
```

### 4. 确认 OpenClaw 目录

```bash
ls ~/.openclaw/workspace/MEMORY.md       # 长期记忆
ls ~/.openclaw/workspace/memory/          # daily notes
ls ~/.openclaw/workspace/SOUL.md          # 身份定义 (sync-config 会收集)
ls ~/.openclaw/workspace/HEARTBEAT.md     # 心跳配置
ls ~/.openclaw/workspace/USER.md          # 用户信息
```

### 5. 首次收割测试

```bash
cd ~/memory-vault
export MEMORY_VAULT=~/memory-vault VAULT_ROOT=~/memory-vault
export MODULE_DIR=~/memory-vault/modules/harvest
bash modules/harvest/run.sh
```

---

## Android Termux 部署

> 适用于: 安卓手机, Termux 中使用 Gemini CLI

### 1. 前置准备

```bash
# 安装 Termux (从 F-Droid, 不要用 Google Play 版)
# 打开 Termux 后:
pkg update && pkg upgrade
pkg install git curl openssh python nodejs-lts
```

### 2. 一键安装

```bash
# 先把 termux-setup.sh 传到手机 (或 curl 下载)
# 方法1: 从 vault clone 后执行
git clone git@gitlab.your-ddns.com:user/memory-vault.git ~/memory-vault
bash ~/memory-vault/core/termux-setup.sh git@gitlab.your-ddns.com:user/memory-vault.git

# 方法2: 直接从另一台机器 scp
# scp user@mac-a:~/AI-local/memory-vault-modular/core/termux-setup.sh ~/
# bash ~/termux-setup.sh git@gitlab.your-ddns.com:user/memory-vault.git
```

setup 脚本会自动:
- 尝试编译安装 jj (失败则用 git 兼容模式)
- 安装 Gemini CLI
- 生成 SSH key (需要你手动添加到 GitLab)
- 克隆 vault
- 创建 Termux 专用收割脚本
- 配置 cronie 定时任务
- 注册到 projects.json
- 配置 GEMINI.md 集成说明
- 首次收割

### 3. 定时任务

```bash
# 方式1: cronie (setup 自动配置)
# 每次重启 Termux 后需要启动 crond:
crond

# 建议在 ~/.bashrc 加入:
echo 'pgrep crond >/dev/null || crond' >> ~/.bashrc

# 方式2: termux-job-scheduler (需要 Termux:API app)
pkg install termux-api
termux-job-scheduler --job-id 1 --period-ms 10800000 \
  --script "$HOME/memory-vault/scripts/harvest-termux.sh"

# 方式3: 每次打开 Termux 手动跑
bash ~/memory-vault/scripts/harvest-termux.sh
```

### 4. Termux 注意事项

| 事项 | 说明 |
|---|---|
| **jj 编译** | 在手机上编译 Rust 可能需要 10-20 分钟且占用大量内存, 编译失败会自动降级到 git |
| **后台运行** | Android 会杀后台进程, Termux 需要开启通知栏常驻 (Termux 设置 → Acquire wake lock) |
| **电池** | 每 3 小时收割对电量影响很小, 主要是 git push 的网络请求 |
| **存储** | conversations/ 归档会占空间, 定期在 Mac 上运行 `jj-admin.sh gc` |
| **网络** | 手机在局域网2 WiFi 时走 Surge, 用移动数据时需要确保能访问 GitLab (DDNS) |
| **仅收割 Gemini** | Termux 版只收割 Gemini CLI 记忆和对话, 不收其他工具 |

---

## Windows 部署

> 注意事项较多, 建议优先使用 WSL2

### 方案 A: WSL2 (推荐)

```powershell
# 1. 启用 WSL2 (如果没有)
wsl --install -d Ubuntu-24.04

# 2. 进入 WSL
wsl
```

在 WSL 内部, 按 **Ubuntu 部署** 的步骤操作。

**重要**: 把仓库 clone 在 Linux 文件系统中 (`~/memory-vault`), 不要放在 `/mnt/c/` 下。
`/mnt/c/` 下所有文件会被标记为 executable, 导致 jj 产生大量无意义变更。

如果需要收割 Windows 端工具的记忆:

```bash
# 在 WSL 中访问 Windows 端的 Claude CLI 记忆
# Claude CLI on Windows 存储在: C:\Users\{user}\.claude\
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
CLAUDE_WIN="/mnt/c/Users/$WIN_USER/.claude/memory"

if [ -d "$CLAUDE_WIN" ]; then
  mkdir -p ~/memory-vault/raw/claude/windows/_global
  cp "$CLAUDE_WIN"/*.md ~/memory-vault/raw/claude/windows/_global/
fi
```

### 方案 B: 原生 Windows (Git Bash)

```powershell
# 1. 安装 jj
# 下载: https://github.com/jj-vcs/jj/releases
# 选择 jj-v*-x86_64-pc-windows-msvc.zip
# 解压到 C:\Program Files\jj\ 并添加到 PATH

# 2. 启用开发者模式 (支持 symlinks)
# 设置 → 更新和安全 → 开发者选项 → 开发人员模式: 开

# 3. Git Bash 中操作
jj git clone --colocate git@gitlab.your-ddns.com:user/memory-vault.git ~/memory-vault

# 4. 定时任务: 用 Task Scheduler
# 操作: "C:\Program Files\Git\bin\bash.exe" -c "cd ~/memory-vault && bash modules/harvest/run.sh"
# 触发: 每3小时
```

**Windows 注意事项**:
- `jj` 在 Windows 上功能完整, 但有 [symlink 和换行符问题](https://docs.jj-vcs.dev/latest/windows/)
- 建议在 `config.toml` 中设置 `working-copy.eol-conversion = "native"`
- 推荐 WSL2 方案, 体验与 Linux 一致

---

## 让各工具知道这个系统

这是最关键的一步: 告诉每个 AI 工具如何与 memory-vault 配合。

### Claude CLI

在 `~/.claude/CLAUDE.md` (全局) 中添加:

```markdown
## Memory Vault 跨工具记忆系统

本机已部署 memory-vault 跨工具记忆同步系统。

### 你应该知道的:
- 你的记忆文件 (`~/.claude/memory/`) 每3小时自动同步到 memory-vault
- 其他工具 (Gemini/Antigravity/OpenClaw/Codex) 的蒸馏知识会自动出现在
  `~/.claude/memory/cross_tool_context.md` 中
- 按项目的跨工具知识会出现在对应项目的 memory 目录中

### 最佳实践:
- 重要决策请写入 memory (type: feedback 或 project), 它们会被同步
- 不需要手动管理跨工具同步, 系统自动处理
- 如果发现 cross_tool_context.md 中的信息过时, 属于正常现象, 下次蒸馏会更新
```

对于每个项目, 在项目根目录的 `CLAUDE.md` 中添加:

```markdown
## 跨工具上下文

本项目通过 memory-vault 与其他 AI 工具共享知识。
跨工具蒸馏的记忆会自动出现在本项目的 memory 目录中。
```

### Gemini CLI

在 `~/.gemini/GEMINI.md` (全局) 中添加:

```markdown
## Memory Vault Integration

This machine runs a cross-tool memory synchronization system (memory-vault).

What you should know:
- Your memories (## Gemini Added Memories) are synced every 30 minutes
- Cross-tool knowledge from Claude/Antigravity/OpenClaw/Codex appears in
  the "## Cross-Tool Context" section below (auto-synced, do not edit)
- Your conversation history is archived before the 30-day auto-cleanup

Best practices:
- Use `save_memory` for important decisions — they will be synced cross-tool
- The "## Cross-Tool Context" section is auto-managed, do not edit it manually
```

对于每个项目, 在项目根目录的 `GEMINI.md` 中添加:

```markdown
## Cross-Tool Integration

This project uses memory-vault for cross-tool knowledge sharing.
Cross-tool context is auto-synced in the "## Cross-Tool Context" section of ~/.gemini/GEMINI.md.
```

### OpenClaw

在 `~/.openclaw/workspace/MEMORY.md` 中添加:

```markdown
## Memory Vault Integration

This machine runs memory-vault for cross-tool memory synchronization.

- Daily notes (memory/*.md) are archived and distilled automatically
- Cross-tool knowledge from Claude/Gemini/Antigravity/Codex appears in
  the "## Cross-Tool Knowledge" section (auto-synced, do not edit)
- MEMORY.md, SOUL.md, HEARTBEAT.md, USER.md are synced across machines
  via the sync-config module

Best practices:
- Write important discoveries to MEMORY.md — they will be shared cross-tool
- The "## Cross-Tool Knowledge" section is auto-managed
```

### Codex CLI

在 `~/.codex/AGENTS.md` 中添加:

```markdown
## Memory Vault Integration

This machine uses memory-vault for cross-tool memory synchronization.

- AGENTS.md content is synced every 30 minutes
- Cross-tool knowledge from Claude/Gemini/Antigravity/OpenClaw appears in
  the "## Cross-Tool Context" section (auto-synced, do not edit)

Best practices:
- Write important decisions in this file — they will be shared cross-tool
- The "## Cross-Tool Context" section is auto-managed
```

### Antigravity

Antigravity 的 knowledge base 是自动收集的, 不需要额外配置。
它的 brain/ 目录下的知识会被自动归档到 memory-vault。

如果想让 Antigravity 知道其他工具的知识, 可以在项目的 `GEMINI.md` 中添加
(Antigravity 底层使用 Gemini, 会读取 GEMINI.md):

```markdown
## Cross-Tool Context

This project has knowledge synced from other AI tools (Claude, OpenClaw, Codex).
Check ~/.gemini/GEMINI.md for the latest cross-tool context.
```

---

## 验证部署

### 每台机器上执行:

```bash
cd ~/memory-vault

# 1. 查看仓库状态
source core/module-loader.sh
VAULT_ROOT=~/memory-vault bash modules/admin/run.sh status

# 2. 查看已注册的项目
cat projects.json | python3 -m json.tool

# 3. 手动收割一次
export MEMORY_VAULT=~/memory-vault VAULT_ROOT=~/memory-vault
export MODULE_DIR=~/memory-vault/modules/harvest
bash modules/harvest/run.sh

# 4. 检查 raw/ 是否有数据
find raw/ -type f | head -20

# 5. 检查 conversations/ 是否有数据
find conversations/ -type f | head -10

# 6. 查看 jj log
jj log --limit 5
```

### GitLab CI 验证:

```
1. 在 GitLab UI 手动触发 Pipeline (Run pipeline)
2. 观察 5 个阶段是否依次通过:
   L0 → L1 → L2 → L3 → writeback
3. 检查 artifacts 是否生成:
   distilled/L0/, L1/, L2/, L3/, writeback/
```

### 端到端验证:

```bash
# Mac A 上:
# 1. 用 Claude 在某个项目里写一条 memory
#    (Claude 会话中说 "记住: 这个项目用 JWT 做认证")

# 2. 等待3小时 (或手动触发 harvest)

# 3. 在 GitLab 手动触发 Pipeline

# 4. Mac B 上手动触发 harvest (拉取回写)
cd ~/memory-vault
bash modules/harvest/run.sh

# 5. 在 Mac B 上检查对应项目的 Claude memory
ls ~/.claude/projects/*/memory/cross_tool_context.md
cat ~/.claude/projects/-Users-yaya-Developer-{project}/memory/cross_tool_context.md

# 如果看到 Mac A 上写的 "JWT 做认证", 端到端验证成功
```

---

## 注意事项

### 通用

| 事项 | 说明 |
|---|---|
| **jj 版本** | 所有机器统一 ≥0.25, 避免 bookmark 命令不兼容 |
| **SSH Key** | 每台机器用独立 SSH key, 全部添加到 GitLab |
| **时区** | CI schedule 使用 GitLab 服务器时区, 确认凌晨3点是你想要的 |
| **首次运行** | 第一次 Pipeline 可能因为 `raw/` 和 `conversations/` 为空而跳过蒸馏, 属正常 |
| **Gemini 速率** | Gemini CLI 免费额度有限, L0/L2/L3 中加了 `sleep 3`, 大量对话时注意 |
| **磁盘空间** | `conversations/` 会持续增长, 定期运行 `jj-admin.sh gc` 清理 |

### Mac 特有

| 事项 | 说明 |
|---|---|
| **launchd 权限** | 如果 harvest 无法访问某些目录, 需要在 系统设置 → 隐私与安全 → 完全磁盘访问 中允许 `/bin/bash` |
| **Antigravity 路径** | 默认搜索 `~/projects ~/Developer ~/code`, 如果项目在其他位置需要修改 `config/machines.json` |
| **brew 更新 jj** | `brew upgrade jj` 可能改变行为, 建议固定版本或测试后再升级 |

### Ubuntu (CI Runner)

| 事项 | 说明 |
|---|---|
| **Runner executor** | 建议 Docker executor, 每个 job 隔离环境 |
| **npm cache** | Gemini CLI 每次 job 都重新安装, 可以配置 npm cache 加速 |
| **git config** | writeback stage 需要 `git config`, 已在 CI 中配置 |

### Debian (OpenClaw)

| 事项 | 说明 |
|---|---|
| **Python 版本** | 需要 Python 3.10+, `python3 --version` 确认 |
| **OpenClaw 更新** | OpenClaw 更新后目录结构可能变化, 注意检查 |
| **cron 日志** | 查看 `/tmp/memory-harvest.log` 排查问题 |

### Windows

| 事项 | 说明 |
|---|---|
| **强烈推荐 WSL2** | 原生 Windows 有 symlink 和 EOL 问题 |
| **文件系统** | WSL 中仓库必须在 Linux 文件系统 (`~/`), 不要放 `/mnt/c/` |
| **跨文件系统收割** | 从 WSL 读 Windows 端工具记忆走 `/mnt/c/Users/{user}/.claude/` |
| **开发者模式** | 原生 Windows 使用 jj 需要开启开发者模式 (支持 symlinks) |

### 网络相关

| 事项 | 说明 |
|---|---|
| **局域网2 → GitLab** | 确认 `git@gitlab.your-ddns.com` SSH 可达: `ssh -T git@gitlab.your-ddns.com` |
| **Surge 规则** | 确保 GitLab SSH (端口 2222 或 22) 走 Snell 隧道 |
| **DDNS 更新** | 如果公网 IP 变化, Lucky 的 DDNS 需要及时更新 |
| **离线工作** | harvest 在无网络时跳过 push, 下次有网络时自动同步 |
