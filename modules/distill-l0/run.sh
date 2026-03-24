#!/bin/bash
# distill-l0/run.sh — 对话蒸馏入口
set -euo pipefail
cd "$VAULT_ROOT"
echo "=== L0: Extract conversations ==="
python3 "$MODULE_DIR/extract.py"

echo "=== L0: Distill with Gemini CLI ==="
bash "$MODULE_DIR/distill.sh"
