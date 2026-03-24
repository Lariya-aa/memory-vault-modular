#!/bin/bash
# project-register.sh — 扫描本机 git 项目，注册到 projects.json
#
# 解决的问题: 同一个项目在不同机器上路径不同，
# 用 git remote URL 作为 canonical ID 跨机器关联。
#
# 用法:
#   bash core/project-register.sh                 # 扫描默认路径
#   bash core/project-register.sh ~/my-projects   # 扫描指定路径
#
set -euo pipefail

VAULT_ROOT="${MEMORY_VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECTS_FILE="$VAULT_ROOT/projects.json"
MACHINE=$(hostname -s)
CONFIG_FILE="$VAULT_ROOT/config/machines.json"

# 初始化 projects.json
if [ ! -f "$PROJECTS_FILE" ]; then
  echo '{"_global":{"description":"跨项目全局记忆"}}' > "$PROJECTS_FILE"
fi

# 读取搜索路径
SEARCH_ROOTS="${*:-}"
if [ -z "$SEARCH_ROOTS" ]; then
  SEARCH_ROOTS=$(python3 -c "
import json, os
cfg = json.load(open('$CONFIG_FILE')) if os.path.exists('$CONFIG_FILE') else {}
roots = cfg.get('defaults', {}).get('antigravity_roots', ['~/projects', '~/Developer', '~/code'])
print(' '.join(os.path.expanduser(r) for r in roots))
" 2>/dev/null || echo "$HOME/projects $HOME/Developer $HOME/code")
fi

echo "=== Project Registration ==="
echo "Machine: $MACHINE"
echo "Search: $SEARCH_ROOTS"
echo ""

# Claude project dir 编码: /Users/yaya/projects/foo → -Users-yaya-projects-foo
path_to_claude_dir() {
  echo "$1" | sed 's|^/|-|' | tr '/' '-'
}

# Gemini project hash: SHA256 前 16 位
path_to_gemini_hash() {
  echo -n "$1" | shasum -a 256 2>/dev/null | cut -c1-16 || \
  echo -n "$1" | sha256sum 2>/dev/null | cut -c1-16 || \
  echo "unknown"
}

# 从 git remote 提取项目名: git@host:user/my-api.git → my-api
remote_to_name() {
  local remote="$1"
  basename "$remote" .git
}

REGISTERED=0

for root in $SEARCH_ROOTS; do
  [ -d "$root" ] || continue

  for project_dir in "$root"/*/; do
    [ -d "$project_dir" ] || continue

    # 检查是否是 git 仓库
    if ! git -C "$project_dir" rev-parse --git-dir &>/dev/null; then
      continue
    fi

    # 获取 remote URL
    remote=$(git -C "$project_dir" remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote" ]; then
      continue
    fi

    canonical=$(remote_to_name "$remote")
    abs_path=$(cd "$project_dir" && pwd)
    claude_dir=$(path_to_claude_dir "$abs_path")
    gemini_hash=$(path_to_gemini_hash "$abs_path")

    # 注册到 projects.json
    python3 -c "
import json, sys

projects = json.load(open('$PROJECTS_FILE'))

name = '$canonical'
if name not in projects:
    projects[name] = {'git_remote': '$remote', 'machines': {}}
elif 'machines' not in projects[name]:
    projects[name]['machines'] = {}

projects[name]['git_remote'] = '$remote'
projects[name]['machines']['$MACHINE'] = {
    'path': '$abs_path',
    'claude_project_dir': '$claude_dir',
    'gemini_project_hash': '$gemini_hash',
}

json.dump(projects, open('$PROJECTS_FILE', 'w'), ensure_ascii=False, indent=2)
"
    echo "  Registered: $canonical ($abs_path)"
    REGISTERED=$((REGISTERED + 1))
  done
done

# 注册 Claude 的 home 目录项目为 _global
HOME_CLAUDE_DIR=$(path_to_claude_dir "$HOME")
python3 -c "
import json
projects = json.load(open('$PROJECTS_FILE'))
g = projects.setdefault('_global', {'description': '跨项目全局记忆'})
machines = g.setdefault('machines', {})
machines['$MACHINE'] = {
    'path': '$HOME',
    'claude_project_dir': '$HOME_CLAUDE_DIR',
}
json.dump(projects, open('$PROJECTS_FILE', 'w'), ensure_ascii=False, indent=2)
"

echo ""
echo "Registered $REGISTERED projects + _global for $MACHINE"
