# Memory Vault

[**🇨🇳 简体中文**](README_zh.md) | [**🇺🇸 English**](README.md)

> **✨ 100% Vibe Coding Project**: This entire architecture, codebase, and distillation pipeline was built purely through AI interactions without manual coding.

A cross-network, cross-platform, cross-tool AI Agent memory and conversation distillation system.

Built on [jj (Jujutsu)](https://github.com/jj-vcs/jj) version control + GitLab CI + Gemini CLI.

## The Problem It Solves

You explore a project architecture using Claude CLI on Mac A, then go home and continue with Gemini CLI on Mac B, but the AI remembers nothing.

Memory Vault automatically harvests memory and conversations from all AI tools, distills and purifies them, and writes them back into each tool's native format. This allows you to seamlessly continue your work across any machine and any tool.

```
Mac A (Claude/Gemini/Antigravity)     Mac B (Claude/Gemini/Codex)
         ↓ harvest                              ↓ harvest
         ↓ (Auto every 3 hours)                  ↓
    ┌────────────────────────────────────────────────┐
    │           GitLab (memory-vault repo)           │
    │                     ↓ CI                       │
    │ L0 Conversation Distillation → L1 Dedup        │
    │ → L1.5 Content Classification                  │
    │ → L2 Semantic Merge → L3 Global Refinement     │
    │ → writeback                                    │
    └────────────────────────────────────────────────┘
         ↓ writeback                            ↓ writeback
  Claude reads Gemini's knowledge     Gemini reads Claude's knowledge
  Gemini reads OpenClaw's insights    All tools share distilled memory
```

## Supported Tools

| Tool | Harvests | Writeback Location |
|---|---|---|
| Claude CLI | Memory (`~/.claude/projects/*/memory/`) + Chat (`.jsonl`) | Appended to `~/.claude/memory/cross_tool_context.md` |
| Gemini CLI | Memory (`GEMINI.md`) + Chat (`~/.gemini/tmp/*/chats/`) | Appended to `GEMINI.md` (`## Cross-Tool Context`) |
| Antigravity | Knowledge Base (`.gemini/antigravity/brain/`) | Synced via `GEMINI.md` |
| OpenClaw | `MEMORY.md` + daily notes | Appended to `MEMORY.md` |
| Codex CLI | `AGENTS.md` | Appended to `AGENTS.md` |

## Supported Platforms

| Platform | Deployment | Scheduler |
|---|---|---|
| macOS | `bash wizard.sh` | launchd (Every 3 hours) |
| Linux (Ubuntu/Debian) | `bash wizard.sh` | cron (Every 3 hours) |
| Android (Termux) | `bash core/termux-setup.sh` | cronie / Manual |
| Windows | WSL2 (Same as Linux) | cron in WSL |

## Distillation Pipeline & Anti-Overflow Protection (3-Layer)

```
harvest      Harvest tool memory & conversations (All into _global)
    ↓
L0           Gemini CLI extracts decision/preference/knowledge
             [Layer 1 Source Throttling] Dynamically abandons useless debug logs, 0-5 key facts per turn.
    ↓
L1           Pure Python deduplication & format normalization
    ↓
L1.5         Gemini CLI categorizes content into projects (No pre-registration needed)
(classify)   Auto-discovers new project topics, solves fragmentation.
    ↓
L2           Gemini CLI cross-tool semantic merging by project
             [Layer 2 Budget Eviction] Enforces $BUDGET limit. Compresses/Abandons low-priority memory (Decision > Todo).
    ↓
L3           Gemini CLI global distillation & project refinement
    ↓
writeback    Distilled output → Native formats → Automatically injected on pull
             [Layer 3 Safety Truncation] Final writeback truncation (budget_truncate) entirely eradicates tool context overflow risk.
```

## Role of JJ (Jujutsu)

| Feature | Stage | Purpose |
|---|---|---|
| No staging area | harvest | Auto-tracks changes, skips `git add` |
| Change ID | harvest | Cross-machine change references |
| `jj describe` | harvest / writeback | Structured metadata annotation |
| `jj bookmark` | writeback | Tracks distillation progress (cursors) |
| `jj undo` | writeback | One-click rollback on error |
| `jj split` | admin | Split mixed harvests by tool |
| `jj squash` | admin | Merge sequential distill changes |
| Operation Log | admin | Cross-machine operation audit |
| Lock-free concurrency | harvest push | Prevents collisions from multi-machine pushes |

## Directory Structure

```
memory-vault-modular/
│
├── wizard.sh                              Interactive management terminal (1. Deploy 2. Sync to Private Vault)
├── .gitlab-ci.example.yml                 CI Pipeline Template (6 stages, isolated IP)
├── .gitignore                             Strict isolation rules (blocks private logs & configs)
├── projects.example.json                  Project Registry Template
│
├── core/                                  Core tools (jj-utils, module-loader, setup, etc)
├── config/                                Config Templates (modules, machines)
├── configs/                               Tool Configuration Templates (Cross-platform syncing)
├── modules/                               Functional Modules (harvest, distill L0-L3, classify, writeback, admin)
├── launchd/                               macOS task triggers
```

## Quick Start

### Initial Setup (First Machine)
```bash
bash wizard.sh
```
Follow the interactive wizard. See [DEPLOY.md](DEPLOY.md) for details.

### Subsequent Machines
```bash
bash wizard.sh
# Automatically pulls configuration templates from the vault and injects them locally
```

### Source Code Sync to Private Vault
If you modify this modular codebase (`memory-vault-modular`) and want to sync the logic updates to your personal running vault:
```bash
bash wizard.sh
# Select [2] Source Code Sync in the interactive menu
```
The wizard will safely `rsync` the core logic into your final deployment repository, strictly bypassing and protecting your environment JSON configs, private memory corpus, and deployment CI pipelines.

## Documentation
- [DEPLOY_en.md](DEPLOY_en.md) — Deployment guide (Mac/Ubuntu/Debian/Termux/Windows)
- [CHANGELOG.md](CHANGELOG.md) — Version updates

## Dependencies
| Tool | Purpose | Install |
|---|---|---|
| [jj](https://github.com/jj-vcs/jj) >= 0.25 | Version Control | `brew install jj` / Official Script |
| Python >= 3.10 | L1 Dedup / Writeback | Native or `brew install python` |
| Node.js >= 18 | Gemini CLI Runtime | `brew install node` |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | L0-L3 Distillation Engine | `npm install -g @google/gemini-cli` |
| Git | jj Backend | Native |

## License
[MIT](LICENSE)
