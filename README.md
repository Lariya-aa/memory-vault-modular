# Memory Vault

跨网络、跨平台、跨工具的 AI Agent 记忆与对话蒸馏系统。

基于 [jj (Jujutsu)](https://github.com/jj-vcs/jj) 版本控制 + GitLab CI + Gemini CLI 构建。

## 解决什么问题

你在 Mac A 上用 Claude CLI 探索了一个项目方案，回家后在 Mac B 上用 Gemini CLI 继续时，AI 什么都不记得。

Memory Vault 自动收割所有 AI 工具的记忆和对话，蒸馏提纯后回写到各工具的原生格式，让你在任何机器、任何工具上都能继续之前的工作。

```
Mac A (Claude/Gemini/Antigravity)     Mac B (Claude/Gemini/Codex)
         ↓ harvest                              ↓ harvest
         ↓ (每30分钟自动)                        ↓
    ┌────────────────────────────────────────────────┐
    │              GitLab (memory-vault repo)         │
    │                     ↓ CI                        │
    │    L0 对话蒸馏 → L1 去重 → L1.5 按内容分类      │
    │    → L2 跨工具合并 → L3 全局精炼 → writeback    │
    └────────────────────────────────────────────────┘
         ↓ writeback                            ↓ writeback
  Claude 看到 Gemini 的知识            Gemini 看到 Claude 的知识
  Gemini 看到 OpenClaw 的发现          所有工具共享蒸馏后的记忆
```

## 支持的工具

| 工具 | 收割内容 | 回写位置 |
|---|---|---|
| Claude CLI | 记忆 (`~/.claude/projects/*/memory/`) + 对话 (`.jsonl`) | `~/.claude/memory/cross_tool_context.md` |
| Gemini CLI | 记忆 (`GEMINI.md`) + 对话 (`~/.gemini/tmp/*/chats/`) | `GEMINI.md` 追加 `## Cross-Tool Context` |
| Antigravity | 知识库 (`.gemini/antigravity/brain/`) | 通过 `GEMINI.md` |
| OpenClaw | `MEMORY.md` + daily notes | `MEMORY.md` 追加 `## Cross-Tool Knowledge` |
| Codex CLI | `AGENTS.md` | `AGENTS.md` 追加 `## Cross-Tool Context` |

## 支持的平台

| 平台 | 部署方式 | 定时任务 |
|---|---|---|
| macOS | `bash wizard.sh` | launchd (每30分钟) |
| Linux (Ubuntu/Debian) | `bash wizard.sh` | cron (每30分钟) |
| Android (Termux) | `bash core/termux-setup.sh` | cronie / 手动 |
| Windows | WSL2 (按 Linux 部署) | cron in WSL |

## 蒸馏管线与防溢出护城河 (3-Layer Protection)

```
harvest      收割各工具记忆和对话 (全归 _global)
    ↓
L0           Gemini CLI 从对话中提取 decision/preference/knowledge
             [Layer 1 源头限流] 动态抛弃无效调试日志，每轮限提取 0-5 条关键事实。
    ↓
L1           纯 Python 去重 + 格式标准化
    ↓
L1.5         Gemini CLI 按内容自动分类到项目 (不需要预先注册项目)
(classify)   自动发现新项目主题，提高并确立项目成立阈值，解决项目碎片化。
    ↓
L2           Gemini CLI 按项目跨工具语义合并
             [Layer 2 预算淘汰] 强制引入 $BUDGET 机制。按照优先级 (Decision > Todo) 自动压缩/抛弃低权记忆。
    ↓
L3           Gemini CLI 全局蒸馏 + 按项目精炼
    ↓
writeback    蒸馏结果 → 各工具原生格式 → 各机器 pull 后自动注入
             [Layer 3 安全兜底] 回写终点执行极限截断 (budget_truncate)，根绝任何工具的 Context 撑爆风险。
```

## jj 在工作流中的作用

| jj 特性 | 使用位置 | 作用 |
|---|---|---|
| 无 staging area | harvest | 文件变更自动追踪，省去 `git add` |
| Change ID (稳定引用) | harvest | 跨机器关联同一次收割，不随 amend 变化 |
| `jj describe` | harvest / writeback | 结构化元数据注解 |
| `jj bookmark` | writeback | 标记蒸馏进度，支持增量处理 |
| `jj undo` | writeback | 蒸馏出错一键回滚 |
| `jj split` | admin | 按工具拆分混合收割 |
| `jj squash` | admin | 合并连续蒸馏 change |
| Operation Log | admin | 跨机器操作审计 |
| Lock-free 并发 | harvest push | 多机器同时 push 不冲突 |

## 目录结构

```
memory-vault-modular/
│
├── wizard.sh                              交互式管控终端 (1.部署新机器环境 2.将核心增量安全 Sync 给私库)
├── .gitlab-ci.example.yml                 CI 管线模板 (6阶段全自动，已抽离私密通信 IP)
├── .gitignore                             强一致隔离规则 (屏蔽提交个人私有日志和运行配仓)
├── projects.example.json                  项目注册表模板
│
├── core/                                  核心层 (所有模块依赖)
│   ├── jj-utils.sh                        jj 工具函数库
│   │                                        jj_change_id()     获取稳定 Change ID
│   │                                        jj_describe_harvest()  结构化元数据
│   │                                        jj_set_bookmark()   兼容多版本 bookmark 操作
│   │                                        jj_push()           移动 bookmark + push
│   │                                        jj_has_changes()    检测工作拷贝变更
│   ├── module-loader.sh                   模块加载器
│   │                                        run_module()   运行单个模块
│   │                                        run_pipeline() 按顺序运行整个管线
│   │                                        list_modules() 列出模块状态
│   │                                        is_module_enabled() 检查模块开关
│   ├── project-register.sh                项目注册 (扫描 git remote → canonical ID)
│   ├── setup.sh                           非交互式安装 (wizard 的底层实现)
│   └── termux-setup.sh                    Android Termux 专用安装脚本
│
├── config/                                配置文件模板
│   ├── modules.example.json               模块启用/禁用开关示例
│   └── machines.example.json              机器配置示例 (Antigravity 搜索路径等)
│
├── configs/                               工具配置同步 (运行时生成)
│   └── _templates/                        配置模板 (一次编辑，全平台生效)
│       ├── claude-global.md               → 注入 ~/.claude/CLAUDE.md
│       ├── claude-project.md              → 注入 项目/CLAUDE.md
│       ├── gemini-global.md               → 注入 ~/.gemini/GEMINI.md
│       ├── gemini-project.md              → 注入 项目/GEMINI.md
│       ├── openclaw-memory.md             → 注入 MEMORY.md
│       ├── openclaw-soul.md               → 注入 SOUL.md
│       ├── openclaw-user.md               → 注入 USER.md
│       └── codex-global.md               → 注入 ~/.codex/AGENTS.md
│
├── modules/                               功能模块 (按需启用)
│   │
│   ├── harvest/                           [管线] 收割各工具记忆和对话
│   │   ├── module.json                    模块元数据 (名称/依赖/阶段)
│   │   └── run.sh                         入口: 回写分发 → 收割记忆 → 收割对话 → jj push
│   │                                        直接扫描 ~/.claude/projects/ (不依赖 projects.json)
│   │                                        Gemini 对话全收到 _global (由 classify 按内容分类)
│   │
│   ├── distill-l0/                        [管线] L0: 对话 → 结构化知识
│   │   ├── module.json
│   │   ├── run.sh                         入口: 先 extract 再 distill
│   │   ├── extract.py                     解析 Claude JSONL / Gemini JSON / Codex JSONL
│   │                                        提取 user/assistant 对话轮次
│   │                                        格式化为 Markdown 供 Gemini 蒸馏
│   │   └── distill.sh                     Gemini CLI 逐个对话提取 decision/preference/knowledge
│   │                                        输出 JSON 数组，合并为 _l0_merged.json
│   │
│   ├── distill-l1/                        [管线] L1: 去重 + 按项目分组
│   │   ├── module.json
│   │   ├── run.sh                         入口: jj log 统计待处理量 → dedup.py
│   │   └── dedup.py                       纯 Python，零 LLM
│   │                                        jj log + jj diff 增量提取 (只处理新 harvest)
│   │                                        收集 L0 对话蒸馏输出 (_l0_merged.json)
│   │                                        内容哈希去重，按项目分组输出 JSON
│   │
│   ├── classify/                          [管线] L1.5: 按内容自动分类到项目
│   │   ├── module.json
│   │   └── run.sh                         Gemini CLI 根据内容判断每条知识属于哪个项目
│   │                                        读取已知项目列表 + L3 历史摘要作为参考
│   │                                        自动发现新项目，追加到 projects.json
│   │                                        首次运行全归 _global，后续越跑越准
│   │
│   ├── distill-l2/                        [管线] L2: 跨工具语义合并
│   │   ├── module.json
│   │   ├── run.sh                         入口
│   │   └── merge.sh                       Gemini CLI 按项目合并
│   │                                        识别不同工具/不同说法表达同一件事
│   │                                        保留跨工具来源标注 [claude@mac-a, gemini@mac-b]
│   │                                        矛盾记录标注 [冲突]
│   │
│   ├── distill-l3/                        [管线] L3: 全局 + 按项目精炼
│   │   ├── module.json
│   │   └── run.sh                         Gemini CLI 两层输出:
│   │                                        unified.md  — 全局概览 (所有项目)
│   │                                        projects/{name}.md — 每个项目的精炼摘要
│   │
│   ├── writeback/                         [管线] 蒸馏结果 → 各工具原生格式
│   │   ├── module.json
│   │   ├── run.sh                         入口
│   │   └── generate.py                    按项目生成回写文件
│   │                                        全局: writeback/_global/{tool}/
│   │                                        项目: writeback/{project}/{tool}/
│   │                                        jj describe + bookmark + undo 保护 + push
│   │
│   ├── sync-config/                       [独立] 工具配置同步
│   │   ├── module.json
│   │   ├── run.sh                         两阶段:
│   │   │                                    distribute: 模板 → 注入本地工具 (幂等)
│   │   │                                    collect: 本地工具配置 → vault 归档
│   │   └── init-templates.sh              首次初始化 8 个配置模板
│   │                                        用 <!-- memory-vault-managed --> 标记包裹
│   │                                        修改模板 push 后全平台自动更新
│   │
│   └── admin/                             [独立] jj 管理工具 (手动调用)
│       ├── module.json
│       └── run.sh                         子命令:
│                                            status         bookmark 进度 + 仓库状态
│                                            op-log [N]     跨机器操作历史
│                                            trace <id>     追踪某次收割详情
│                                            split <id>     按工具拆分混合收割
│                                            undo           回滚上一次操作
│                                            squash-distills 合并连续蒸馏 change
│                                            diff-since [bm] 查看自某次蒸馏的变更
│                                            gc [days]      清理过期数据
│
├── launchd/                               macOS 定时任务
│   └── com.user.memory-harvest.plist      每 30 分钟执行 harvest
│
└── 运行时生成的目录 (仅在 ~/memory-vault 中):
    ├── raw/{tool}/{machine}/{project}/    原始记忆文件快照
    ├── conversations/{tool}/{machine}/    对话归档 (防 30 天清理)
    ├── distilled/L0/                      对话蒸馏输出
    ├── distilled/L1/                      去重 + 分组输出
    ├── distilled/L2/                      跨工具合并输出
    ├── distilled/L3/                      全局 + 按项目精炼
    ├── writeback/{project}/{tool}/        回写文件
    └── configs/{tool}/{machine}/          各机器工具配置归档
```

## 快速开始

### 首台机器

```bash
bash wizard.sh
```

向导会引导你完成所有配置。详见 [DEPLOY.md](DEPLOY.md)。

### 后续机器

```bash
bash wizard.sh
# 自动从 vault 拉取配置模板并注入本地工具
```

### 源码更新后同步到私有 Vault

如果您在此开源模块库 (`memory-vault-modular`) 中修改了代码功能，想要同步给您个人的正式运行仓，请直接运行：

```bash
bash wizard.sh
# 并在交互菜单中选择 [2] 仅同步更新代码 (Source Code Sync)
```

向导将通过安全增量的 `rsync` 自动把核心逻辑刷入您最终部署的仓库，**环境配置 JSON、个人私有记忆体、部署后的流水线 YAML** 均会自动跳过保护，绝不覆写。

## 文档

- [DEPLOY.md](DEPLOY.md) — 各平台部署指南 (Mac/Ubuntu/Debian/Termux/Windows)
- [CHANGELOG.md](CHANGELOG.md) — 版本更新日志

## 依赖

| 工具 | 用途 | 安装 |
|---|---|---|
| [jj](https://github.com/jj-vcs/jj) >= 0.25 | 版本控制 | `brew install jj` / 官方安装脚本 |
| Python >= 3.10 | L1 去重 / writeback | 系统自带或 `brew install python` |
| Node.js >= 18 | Gemini CLI 运行环境 | `brew install node` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | L0/L1.5/L2/L3 蒸馏引擎 | `npm install -g @google/gemini-cli` |
| Git | jj 后端 | 系统自带 |

## 许可证

[MIT](LICENSE)
