# Memory Vault Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Wizard Configuration Modes](#wizard-configuration-modes)
3. [Mac Deployment (Claude / Gemini / Antigravity / Codex)](#mac-deployment)
4. [Ubuntu Deployment (GitLab CI/CD Runner)](#ubuntu-deployment)
5. [Debian Deployment (OpenClaw)](#debian-deployment)
6. [Android Termux Deployment (Gemini CLI)](#android-termux-deployment)
7. [Windows Deployment](#windows-deployment)
8. [Connecting External AI Tools](#connecting-external-ai-tools)
9. [Verification](#verification)
10. [Troubleshooting & Notes](#troubleshooting--notes)

---

## Prerequisites

| Requirement | Description |
|---|---|
| GitLab Repository | Create a blank `memory-vault` repository on a self-hosted or public GitLab instance. |
| SSH Key | Ensure your SSH public key is added to GitLab from all connecting machines. |
| Network Bridging | If using hybrid homelabs, ensure cross-LAN connectivity via Surge/Snell or lucky DDNS. |
| jj ≥0.25 | Install Jujutsu (jj) version control on all terminal nodes. |
| Gemini AI Pro | Gemini CLI must be logged in on the local Mac orchestrator. |

---

## Wizard Configuration Modes (Wizard.sh)

Memory Vault ships with an extremely decoupled orchestrator script: `wizard.sh`. Regardless of the network environment or host OS, running `bash wizard.sh` allows you to seamlessly switch between 4 underlying operational modes:

| Option | Mode Name | Deployment Scenario & Under-the-Hood Behavior |
|:---:|---|---|
| **[1]** | **Deploy & Repair**<br>*(Cloud CI Mode)* | **Classic Cloud-driven Architecture.** Ideal for standard multi-node arrays. The wizard establishes local environments and injects a 3-hour OS-level scheduler (launchd/cron) to run `harvest`. The node strictly harvests telemetry to the cloud; heavy LLM distillation is entirely offloaded to the GitLab CI Runner. |
| **[2]** | **Source Code Sync**<br>*(Dev Mode)* | **Hot-Reload Architecture Engine.** Select this when you develop new AI capabilities within the modular source repo. It executes a precise `rsync` transaction that flashes core scripts into your private execution vault, fundamentally bypassing private JSON configs and memory payloads to prevent overwrite disasters. |
| **[3]** | **Local Pipeline Run**<br>*(One-Off Override)* | **The Icebreaker Protocol.** Highly recommended for Day-1 installations. Because historic memory footprints in native AI tools are exceptionally massive, processing them often hits the 60-minute hard timeout on free CI platforms. This mode hijacks your local flagship silicon to blast through L0~L3 uninterrupted, establishing the initial crystal. |
| **[4]** | **Local Daemon Mode**<br>*(Air-Gapped Autopilot)* | **Zero-Server Background Engine.** Ideal if you lack GitLab CI access or demand absolute privacy. The wizard reroutes your OS scheduled tasks to the `local-daemon`. Your workstation evolves into a perpetual, self-contained fusion reactor—running end-to-end extraction and distillation every 3 hours internally, guarded by deterministic `flock` mutexes to prevent temporal collisions. |

---

## Mac Deployment

> Applies to: Dual-Mac setups interacting natively with Claude CLI, Gemini CLI, Antigravity, or Codex CLI.

### 1. Install jj

```bash
brew install jj
jj --version  # Ensure >= 0.25
```

### 2. Initialize Vault

```bash
# Clone the open-source architecture blueprint
cd ~/AI-local
# Run the deployment bootstrapper
bash memory-vault-modular/core/setup.sh git@gitlab.your-ddns.com:user/memory-vault.git
```

`setup.sh` automatically performs:
- Jujutsu identity alignment (`memory-vault@{hostname}`)
- Repository instantiation spanning into `~/memory-vault`
- Indexing all local dev projects into `projects.json`
- Injecting `launchd` background tasks (Every 3 hours)
- Executing the zero-hour genesis harvest

### 3. Verify Scheduled Tasks

```bash
# Confirm launchd integration
launchctl list | grep memory-harvest

# Monitor real-time harvesting logs
tail -20 /tmp/memory-harvest.log
```

---

## Ubuntu Deployment

> Applies to: Ubuntu VMs running GitLab CI/CD Runners.

This machine serves exclusively as the Cloud CI pipeline worker. No local `harvest` operations occur here.

### 1. Configure the CI Pipeline Schedule

```
Within GitLab Web UI:
memory-vault repository → Build → Pipeline schedules → New schedule

Description: Daily Memory Distillation
Interval: 0 */3 * * * (Every 3 hours)
Target Branch: main
Active: ✓
```

---

## Connecting External AI Tools

This is the most critical phase: bridging each AI tool to recognize the memory vault ecosystem.

### Claude CLI
Append to `~/.claude/CLAUDE.md`:
```markdown
## Memory Vault Cross-Tool Integration
- Memories tracked locally (`~/.claude/memory/`) sync every 3 hours into the vault.
- Distilled insights from sibling endpoints (Gemini/Antigravity/OpenClaw/Codex) will organically appear in `~/.claude/memory/cross_tool_context.md`.
```

### Gemini CLI
Append to `~/.gemini/GEMINI.md`:
```markdown
## Memory Vault Cross-Tool Integration
- `save_memory` instructions are globally synced every 3 hours.
- Cross-Tool knowledge automatically feeds into the bottom `## Cross-Tool Context` section. Do not alter it manually.
```

### OpenClaw
Append to `~/.openclaw/workspace/MEMORY.md`:
```markdown
## Memory Vault Cross-Tool Integration
- Daily notes (`memory/*.md`) are extracted and globally distilled every 3 hours.
- The `## Cross-Tool Knowledge` region acts as the unified telemetry receptor.
```

---

## Troubleshooting & Notes

| Subject | Resolution |
|---|---|
| **Daemon Frequencies** | Triggers execute strictly every 3 hours (`10800`s) to drastically optimize Gemini API consumption and limit disruptive background processes. |
| **Mac disk permissions** | If harvesting aborts, grant `/bin/bash` Full Disk Access in macOS Security Preferences. |
| **Storage Overflow** | `conversations/` will bloat gradually. Periodically fire `VAULT_ROOT=~/memory-vault bash modules/admin/run.sh gc 30` to wipe obsolete cache. |
| **Android Termux** | Rust source compilations for `jj` take ~15 minutes and spike RAM limits. The wizard possesses fallback mechanisms to gracefully degrade to standard git logic. |
