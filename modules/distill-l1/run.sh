#!/bin/bash
set -euo pipefail
cd "$VAULT_ROOT"
source "$VAULT_ROOT/core/jj-utils.sh"
jj git init --colocate 2>/dev/null || true

echo "=== Harvest changes since last L1 ==="
if jj bookmark list 2>/dev/null | grep -q "distilled-l1"; then
  jj log -r "distilled-l1..@" --no-graph \
    -T 'if(description.contains("type: harvest"), description.first_line() ++ "\n")' \
    || echo "(none)"
else
  echo "(no bookmark, full scan)"
fi

python3 "$MODULE_DIR/dedup.py"
