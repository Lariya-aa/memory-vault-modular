#!/bin/bash
# jj-utils.sh — jj 工具函数库，被其他脚本 source
# 封装 jj 的核心特性供工作流使用
#
# 最低 jj 版本要求: 0.25+

# 获取当前 change 的 Change ID (稳定引用，不随 amend 变化)
jj_change_id() {
  local rev="${1:-@}"
  jj log -r "$rev" --no-graph -T 'change_id' 2>/dev/null | head -1
}

# 获取当前 change 的 commit ID (git 兼容)
jj_commit_id() {
  local rev="${1:-@}"
  jj log -r "$rev" --no-graph -T 'commit_id' 2>/dev/null | head -1
}

# 用结构化模板描述一个 change
# 用法: jj_describe_harvest <machine> <tools_changed> <file_count>
jj_describe_harvest() {
  local machine="$1"
  local tools="$2"
  local file_count="$3"
  local date
  date=$(date -Iseconds)

  jj describe -m "$(cat <<EOF
harvest: $machine $(date +%F-%H%M)

[metadata]
machine: $machine
timestamp: $date
tools: $tools
files_changed: $file_count
type: harvest
EOF
)"
}

# 用结构化模板描述一个蒸馏 change
# 用法: jj_describe_distill <level> <project_count> <input_change_ids>
jj_describe_distill() {
  local level="$1"
  local project_count="$2"
  local input_changes="$3"
  local date
  date=$(date -Iseconds)

  jj describe -m "$(cat <<EOF
distill: $level $(date +%F)

[metadata]
type: distill-$level
timestamp: $date
projects: $project_count
input_changes: $input_changes
EOF
)"
}

# 从 jj log 中提取特定类型的 change 列表
# 用法: jj_find_changes <type> [since_change_id]
jj_find_changes() {
  local type="$1"
  local since="${2:-root()}"

  jj log -r "$since..@" --no-graph \
    -T 'if(description.contains("type: '"$type"'"), change_id ++ "\n")' \
    2>/dev/null | grep -v '^$'
}

# 获取两个 change 之间变更的文件列表
# 用法: jj_changed_files <from> <to>
jj_changed_files() {
  local from="${1:-@-}"
  local to="${2:-@}"
  jj diff -r "$from" --stat 2>/dev/null
}

# 获取自某个 bookmark 以来的所有 harvest change IDs
# 用法: jj_harvests_since_bookmark <bookmark>
jj_harvests_since_bookmark() {
  local bookmark="${1:-distilled-l1}"
  local base

  if jj bookmark list 2>/dev/null | grep -q "$bookmark"; then
    base="$bookmark"
  else
    base="root()"
  fi

  jj log -r "$base..@" --no-graph \
    -T 'if(description.contains("type: harvest"), change_id ++ "\n")' \
    2>/dev/null | grep -v '^$'
}

# 获取 change 的完整描述 (用于提取元数据)
# 用法: jj_get_description <change_id>
jj_get_description() {
  local change_id="$1"
  jj log -r "$change_id" --no-graph -T 'description' 2>/dev/null
}

# 从 change 描述中提取元数据字段
# 用法: jj_get_meta <change_id> <field>
jj_get_meta() {
  local change_id="$1"
  local field="$2"
  jj_get_description "$change_id" | grep "^${field}:" | head -1 | sed "s/^${field}: *//"
}

# 安全设置 bookmark (兼容 jj ≥0.25: set 自动创建不存在的 bookmark)
# 用法: jj_set_bookmark <name> [revision]
jj_set_bookmark() {
  local name="$1"
  local rev="${2:-@}"
  jj bookmark set "$name" -r "$rev" -B 2>/dev/null || \
    jj bookmark set "$name" -r "$rev" --allow-backwards 2>/dev/null || \
    jj bookmark set "$name" -r "$rev" 2>/dev/null || true
}

# 安全推送: 移动 main bookmark 到最新 change + push
jj_push() {
  jj bookmark set main -r @- -B 2>/dev/null || \
    jj bookmark set main -r @- --allow-backwards 2>/dev/null || \
    jj bookmark set main -r @- 2>/dev/null || true

  jj git push --bookmark main 2>&1 || {
    echo "[jj-push] Push 遇到问题，尝试 fetch 后重推..."
    jj git fetch --all-remotes
    jj bookmark set main -r @- 2>/dev/null || true
    jj git push --bookmark main
  }
}

# 检查工作拷贝是否有变更
jj_has_changes() {
  jj diff --stat 2>/dev/null | grep -q '.'
}

# 打印 operation log (仓库级审计)
jj_op_log() {
  local count="${1:-20}"
  jj op log --limit "$count"
}
