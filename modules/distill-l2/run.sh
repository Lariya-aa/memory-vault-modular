#!/bin/bash
set -euo pipefail
cd "$VAULT_ROOT"
source "$VAULT_ROOT/core/jj-utils.sh"
jj git init --colocate 2>/dev/null || true
bash "$MODULE_DIR/merge.sh"
