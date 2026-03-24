#!/bin/bash
# module-loader.sh — 模块加载器
# 读取 config/modules.json，按依赖顺序执行指定阶段的模块
#
# 用法:
#   source core/module-loader.sh
#   load_module harvest        # 加载单个模块
#   run_pipeline               # 按顺序运行整个蒸馏管线
#   run_module harvest         # 运行单个模块
#   is_module_enabled harvest  # 检查模块是否启用
#
set -euo pipefail

VAULT_ROOT="${MEMORY_VAULT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MODULES_DIR="$VAULT_ROOT/modules"
CONFIG_FILE="$VAULT_ROOT/config/modules.json"

# 加载 jj 工具库
source "$VAULT_ROOT/core/jj-utils.sh"

# 管线阶段顺序 (定义依赖链)
PIPELINE_ORDER=(harvest distill-l0 distill-l1 classify distill-l2 distill-l3 writeback)
# 独立模块 (不在管线中，手动或并行运行)
INDEPENDENT_MODULES=(sync-config admin)

# 检查模块是否启用
is_module_enabled() {
  local module="$1"
  python3 -c "
import json, sys
cfg = json.load(open('$CONFIG_FILE'))
mod = cfg.get('$module', {})
sys.exit(0 if mod.get('enabled', False) else 1)
" 2>/dev/null
}

# 检查模块是否存在
module_exists() {
  local module="$1"
  [ -f "$MODULES_DIR/$module/run.sh" ]
}

# 运行单个模块
run_module() {
  local module="$1"
  shift
  local module_dir="$MODULES_DIR/$module"

  if ! module_exists "$module"; then
    echo "[module-loader] Module '$module' not found"
    return 1
  fi

  if ! is_module_enabled "$module"; then
    echo "[module-loader] Module '$module' is disabled, skipping"
    return 0
  fi

  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  Module: $module"
  echo "═══════════════════════════════════════════════"

  # 导出模块可用的环境变量
  export VAULT_ROOT
  export MODULE_NAME="$module"
  export MODULE_DIR="$module_dir"

  bash "$module_dir/run.sh" "$@"
  local rc=$?

  if [ $rc -eq 0 ]; then
    echo "[module-loader] $module: OK"
  else
    echo "[module-loader] $module: FAILED (exit $rc)"
  fi
  return $rc
}

# 运行整个蒸馏管线 (按顺序)
run_pipeline() {
  echo "=== Memory Vault Pipeline ==="
  echo "Modules: ${PIPELINE_ORDER[*]}"
  echo ""

  local failed=0
  for module in "${PIPELINE_ORDER[@]}"; do
    if is_module_enabled "$module"; then
      run_module "$module" || {
        echo "[pipeline] STOPPED at $module"
        failed=1
        break
      }
    else
      echo "[pipeline] $module: disabled, skipping"
    fi
  done

  # 运行启用的独立模块 (不阻塞管线)
  for module in "${INDEPENDENT_MODULES[@]}"; do
    if is_module_enabled "$module" && module_exists "$module"; then
      echo "[pipeline] Running independent: $module"
      run_module "$module" || true
    fi
  done

  return $failed
}

# 列出所有模块及状态
list_modules() {
  echo "=== Modules ==="
  for module in "${PIPELINE_ORDER[@]}" "${INDEPENDENT_MODULES[@]}"; do
    local status="MISSING"
    if module_exists "$module"; then
      if is_module_enabled "$module"; then
        status="enabled"
      else
        status="disabled"
      fi
    fi
    printf "  %-15s %s\n" "$module" "$status"
  done
}
