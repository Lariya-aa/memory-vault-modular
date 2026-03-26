#!/bin/bash
# distill-l0/distill.sh — Gemini CLI 蒸馏对话 (按项目)
set -euo pipefail

cd "$VAULT_ROOT"
L0_DIR="$VAULT_ROOT/distilled/L0"

LATEST_L0=$(ls -td "$L0_DIR"/*/ 2>/dev/null | head -1)
if [ -z "$LATEST_L0" ]; then
  echo "No conversations extracted, skipping"
  exit 0
fi

DISTILLED_DIR="$LATEST_L0/_distilled"
mkdir -p "$DISTILLED_DIR"

SESSION_COUNT=0
SKIPPED=0

for session_file in "$LATEST_L0"/*.md; do
  [ -f "$session_file" ] || continue
  filename=$(basename "$session_file" .md)

  # [跨端防御] 如果这份文件的 JSON 产物已经存在 (无论是自己生过还是兄弟机推过来的) 则直接跳过
  if [ -f "$DISTILLED_DIR/$filename.json" ]; then
    continue
  fi

  CHAR_COUNT=$(wc -c < "$session_file" | tr -d ' ')
  if [ "$CHAR_COUNT" -lt 500 ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "  Distilling: $filename ($CHAR_COUNT chars)"
  CONVERSATION=$(cat "$session_file")

  PROMPT_FILE="$VAULT_ROOT/configs/_templates/distill-l0-prompt.md"
  if [ -f "$PROMPT_FILE" ]; then
    BASE_PROMPT=$(cat "$PROMPT_FILE")
  else
    BASE_PROMPT="提取长效知识，输出 JSON 数组。"
  fi

  RESULT=$(gemini -p "$BASE_PROMPT
\`\`\`markdown
$CONVERSATION
\`\`\`
" 2>/dev/null || echo "[]")

  if echo "$RESULT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "$RESULT" > "$DISTILLED_DIR/$filename.json"
  else
    CLEANED=$(echo "$RESULT" | python3 -c "
import sys, re, json
text = sys.stdin.read()
match = re.search(r'\[.*\]', text, re.DOTALL)
if match:
    try:
        json.loads(match.group())
        print(match.group())
    except: print('[]')
else: print('[]')
" 2>/dev/null || echo "[]")
    echo "$CLEANED" > "$DISTILLED_DIR/$filename.json"
  fi
  SESSION_COUNT=$((SESSION_COUNT + 1))
  sleep 3
done

# 合并结果
python3 -c "
import json
from pathlib import Path

distilled_dir = Path('$DISTILLED_DIR')
all_entries = []
for f in sorted(distilled_dir.glob('*.json')):
    if f.stem == '_meta': continue
    parts = f.stem.split('-', 2)
    tool = parts[0] if len(parts) > 0 else 'unknown'
    machine = parts[1] if len(parts) > 1 else 'unknown'
    try:
        entries = json.loads(f.read_text())
        if not isinstance(entries, list): continue
        for entry in entries:
            if not isinstance(entry, dict) or not entry.get('content'): continue
            entry['source'] = tool
            entry['machine'] = machine
            entry['origin'] = 'conversation'
            all_entries.append(entry)
    except: pass

output = distilled_dir.parent / '_l0_merged.json'
output.write_text(json.dumps(all_entries, ensure_ascii=False, indent=2))
print(f'L0 merged: {len(all_entries)} entries from {len(list(distilled_dir.glob(\"*.json\")))} sessions')
"

echo "L0 complete: $SESSION_COUNT processed, $SKIPPED skipped"
