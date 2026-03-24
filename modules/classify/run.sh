#!/bin/bash
# classify/run.sh — L1.5: 按内容自动分类知识条目到项目
#
# 输入: distilled/L1/{date}/*.json (去重后的知识条目，全在 _global)
# 输出: distilled/L1/{date}/*.json (重写，每条知识带 project 标签)
#       projects.json (自动发现的新项目会被追加)
#
# 不依赖预先注册的项目。LLM 从内容中发现项目主题。
# 首次运行: 全归 _global + 发现项目列表
# 后续运行: 用已知项目列表做精准分类
#
set -euo pipefail

cd "$VAULT_ROOT"

echo "=== L1.5: Content-based Classification ==="

# 找到最新 L1 输出
L1_DIR="$VAULT_ROOT/distilled/L1"
LATEST_L1=$(ls -td "$L1_DIR"/*/ 2>/dev/null | head -1)
if [ -z "$LATEST_L1" ]; then
  echo "No L1 output, skipping classification"
  exit 0
fi

# 读取已知项目列表 (供 LLM 参考)
KNOWN_PROJECTS="(none yet)"
if [ -f "$VAULT_ROOT/projects.json" ]; then
  KNOWN_PROJECTS=$(python3 -c "
import json
projects = json.load(open('$VAULT_ROOT/projects.json'))
names = [k for k in projects.keys() if k != '_global']
print(', '.join(names) if names else '(none yet)')
" 2>/dev/null || echo "(none yet)")
fi

# 读取 L3 项目摘要 (如果有，供 LLM 参考)
PROJECT_CONTEXT=""
if [ -d "$VAULT_ROOT/distilled/L3/projects" ]; then
  for f in "$VAULT_ROOT/distilled/L3/projects"/*.md; do
    [ -f "$f" ] || continue
    proj=$(basename "$f" .md)
    PROJECT_CONTEXT+="
项目 $proj:
$(head -20 "$f")
"
  done
fi

# 合并所有 L1 条目
ALL_ENTRIES=$(cat "$LATEST_L1"/*.json 2>/dev/null | python3 -c "
import json, sys
all_items = []
for line in sys.stdin:
    try:
        items = json.loads(line)
        if isinstance(items, list):
            all_items.extend(items)
    except: pass
print(json.dumps(all_items, ensure_ascii=False))
" 2>/dev/null || echo "[]")

ENTRY_COUNT=$(echo "$ALL_ENTRIES" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
echo "  Entries to classify: $ENTRY_COUNT"
echo "  Known projects: $KNOWN_PROJECTS"

if [ "$ENTRY_COUNT" -eq 0 ]; then
  echo "  No entries, skipping"
  exit 0
fi

# Gemini CLI 分类
RESULT=$(gemini -p "$(cat <<PROMPT
你是一个知识分类引擎。将知识条目分类到已有项目中。

## 已知项目
$KNOWN_PROJECTS
$PROJECT_CONTEXT

## 知识条目
$ALL_ENTRIES

## 分类规则 (严格按优先级)
1. **优先匹配已有项目** — 宁归已有也不新建
2. 全局偏好/约定/工具配置 → "_global"
3. scope 字段为 "global" 的 → 强制 "_global"
4. **新建项目门槛极高**: 至少 3 条相关知识 + 不是已有项目子话题。不满足则暂归 "_global"
5. 不确定 → "_global"

输出 JSON 数组,每条含原始字段 + "project" 字段。只输出 JSON。
PROMPT
)" 2>/dev/null || echo "")

# 解析结果
python3 << PYEOF
import json, sys, re
from pathlib import Path

vault = Path("$VAULT_ROOT")
latest_l1 = Path("$LATEST_L1")
result_text = '''$RESULT'''

# 尝试解析 LLM 输出
classified = []
try:
    classified = json.loads(result_text)
except:
    match = re.search(r'\[.*\]', result_text, re.DOTALL)
    if match:
        try:
            classified = json.loads(match.group())
        except:
            pass

if not classified:
    print("  Classification failed, keeping all as _global")
    sys.exit(0)

# 按项目分组写入 L1 输出 (覆盖原文件)
by_project = {}
discovered_projects = set()

for entry in classified:
    if not isinstance(entry, dict):
        continue
    proj = entry.get("project", "_global")
    if not proj:
        proj = "_global"
    by_project.setdefault(proj, []).append(entry)
    if proj != "_global":
        discovered_projects.add(proj)

# 写入按项目分组的文件
for proj, entries in by_project.items():
    outfile = latest_l1 / f"{proj}.json"
    outfile.write_text(json.dumps(entries, ensure_ascii=False, indent=2))

# 删除旧的 global.json (已被按项目拆分)
old_global = latest_l1 / "global.json"
if old_global.exists() and len(by_project) > 1:
    old_global.unlink()

# 更新 projects.json (追加新发现的项目)
if discovered_projects:
    pf = vault / "projects.json"
    projects = json.load(open(pf)) if pf.exists() else {"_global": {"description": "跨项目全局记忆"}}

    for proj in discovered_projects:
        if proj not in projects:
            projects[proj] = {
                "discovered_from": "L1.5-classify",
                "description": f"Auto-discovered from conversation content",
                "machines": {},
            }
            print(f"  NEW project discovered: {proj}")

    json.dump(projects, open(pf, "w"), ensure_ascii=False, indent=2)

# 更新 L1 元数据
meta_file = latest_l1 / "_meta.json"
meta = json.load(open(meta_file)) if meta_file.exists() else {}
meta["classified"] = True
meta["projects"] = list(by_project.keys())
meta["project_entry_counts"] = {k: len(v) for k, v in by_project.items()}
meta["discovered_projects"] = list(discovered_projects)
json.dump(meta, open(meta_file, "w"), ensure_ascii=False, indent=2)

print(f"  Classified: {sum(len(v) for v in by_project.values())} entries → {len(by_project)} projects")
for proj, entries in sorted(by_project.items()):
    print(f"    {proj}: {len(entries)} entries")
PYEOF

echo "L1.5 classification complete"
