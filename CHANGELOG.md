# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2026-03-25

### Added
- **LAN Bare Repo Capability**: The configuration wizard natively detects local or mapped network drives (e.g., `file:///mnt/nas`) and gracefully bypasses SSH checks, unlocking 100% offline NAS architectures.
- **Wizard Option [3] Local Pipeline Run**: Bypasses 60-minute CI timeout limits to rapidly execute the L0-L3 distillation pipeline locally, ideal for heavy first-time history merges.
- **Wizard Option [4] Local Daemon Mode**: Pure offline automated distillation architecture. Deploys a background daemon utilizing `flock` kernel mutexes to prevent race conditions on macOS/Linux.
- **Internationalization**: Created full English deployment documentation (`DEPLOY_en.md`).

### Changed
- **Global Scheduled Interval Shifted**: Reduced the default frequency for launchd triggers and cron jobs from `every 30 minutes` to `every 3 hours` (`10800` seconds / `0 */3 * * *`), drastically reducing token burn and OS scheduling overhead.
- **Documentation**: Modernized both READMEs with 100% Vibe Coding badges and synchronized interval specs.
- **L0 Distillation Logic Upgrade**: Externalized the LLM extraction prompt into a modular template (`configs/_templates/distill-l0-prompt.md`). The prompt now explicitly captures 'rejected' choices, infers implicit context, and encapsulates the payload in backticks to prevent prompt injection.
- **Wizard Pipeline Integrity**: Deployment options [1] and [2] now ensure the `wizard.sh` executable and global markdown docs are completely copied over to the active `~/memory-vault`.
- **Cron Concurrency Mutex**: Injected native `flock -n` locks into Termux & Debian cron scheduling to structurally prevent pipeline collision overlaps.
- **Cross-Machine Idempotency**: Fixed a critical L0 flaw where `distill.sh` would re-process files natively synced from neighboring nodes (e.g. over NAS / iCloud). It now structurally checks the existence of `_distilled/` JSON outputs across the multi-agent LAN fleet before firing Gemini CLI calls.

## [0.3.0] - 2026-03-22

### Added
- L1.5 classify 模块: Gemini CLI 按对话内容自动分类到项目
  - 不需要预先注册项目，LLM 从内容中自动发现项目主题
  - 自动追加新发现的项目到 projects.json
  - 首次运行全归 _global，后续越跑越准
- sync-config 双向同步: distribute (模板→本地工具) + collect (本地→vault)
- init-templates.sh: 一次初始化 8 个配置模板，push 后全平台生效
- wizard.sh: 交互式安装向导，新机器一键部署
- termux-setup.sh: Android Termux 专用安装脚本
- DEPLOY.md: 各平台部署指南 (Mac/Ubuntu/Debian/Termux/Windows)
- admin gc: 清理 conversations/ 和 harvest-log

### Fixed
- Claude 收割: 直接扫描 `~/.claude/projects/` 所有目录，不再依赖 `~/.claude/memory/` (可能为空)
- jj_push: push 前自动 `jj bookmark set main -r @-`，解决 bookmark 不跟进问题
- jj bookmark set: 兼容 `--allow-backwards` / `-B` / 无标志，适配不同 jj 版本
- harvest 首次运行: `.last-harvest` 不存在时用 epoch 时间兜底
- Antigravity 路径: 支持 `ANTIGRAVITY_ROOTS` 环境变量配置搜索路径
- jj-utils.sh source 路径: 统一为 `$VAULT_ROOT/core/jj-utils.sh`

### Changed
- .gitlab-ci.yml: 适配 shell executor (去掉 image: 和 before_script 安装步骤)
- Gemini 对话收割: 不再按 hash 映射项目，全收到 _global，由 classify 按内容分类
- harvest.sh 段落替换: 统一为 `replace_section()` 函数，兼容 macOS/Linux

## [0.2.0] - 2026-03-21

### Added
- 模块化架构: core/ + modules/ + config/ 分层
- module-loader.sh: 按需加载模块，`config/modules.json` 控制开关
- project-register.sh: git remote URL 作为跨机器项目唯一标识
- L0 对话蒸馏: extract.py 解析 Claude JSONL / Gemini JSON / Codex JSONL
- distill-l0.sh: Gemini CLI 逐个对话提取知识
- distill-l1 消费 L0 输出: `collect_l0_output()` 合并对话蒸馏到 L1 输入
- 8 个功能模块: harvest, distill-l0, distill-l1, distill-l2, distill-l3, writeback, sync-config, admin
- projects.json: 项目注册表支持跨机器路径映射

### Changed
- 从单体脚本拆分为模块化结构
- 每个模块包含 module.json (元数据) + run.sh (入口)

## [0.1.0] - 2026-03-20

### Added
- 初始版本 (单体架构)
- harvest.sh: 收割 Claude/Gemini/Antigravity/OpenClaw/Codex 记忆
- distill-l1.py: 纯 Python 去重 + jj diff 增量提取
- distill-l2.sh: Gemini CLI 跨工具语义合并
- distill-l3.sh: Gemini CLI 全局蒸馏
- writeback.py: 回写各工具原生格式 + jj bookmark/undo
- jj-utils.sh: jj 工具函数库
- jj-admin.sh: 8 个管理子命令
- .gitlab-ci.yml: 5 阶段 CI 管线
- launchd plist: macOS 定时任务
