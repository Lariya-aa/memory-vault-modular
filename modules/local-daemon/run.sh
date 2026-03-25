#!/bin/bash
# 纯本地断网后台调度器 (Local Daemon)
# 
# 职责: 加上防止并发踩踏的 Linux 文件锁, 然后按顺序全自动唤醒所有蒸馏流水线模块。
# 触发: 由本机的 launchd (Mac) 或 cron (Linux) 每 3 小时触发调用。

set -euo pipefail

# 1. 进程排他锁: 如果上一轮沉重的千字精炼大模型还没跑完，这一次的定时任务唤醒就直接静默放弃
exec 200>/tmp/memory-vault-daemon.lock
flock -n 200 || {
  echo "[$(date)] The local distilling pipeline is still running, skipping this scheduled run."
  exit 0
}

if [ -z "${VAULT_ROOT:-}" ]; then
  # 尝试从路径推算 vault_root
  VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

export MEMORY_VAULT="$VAULT_ROOT"
source "$VAULT_ROOT/core/module-loader.sh"

echo "=== Starting Local Full Pipeline at $(date) ==="

# 2. 从头到尾把所有原本在 GitLab 云端跑的任务，接管到本机纯离线自动化执行
run_module harvest
run_module distill-l0
run_module distill-l1
run_module classify
run_module distill-l2
run_module distill-l3
run_module writeback

echo "=== Finished Local Full Pipeline at $(date) ==="
