#!/usr/bin/env python3
"""L1 蒸馏: jj diff 增量提取 + 纯规则去重 + 按项目分组

jj 特性使用:
  - jj log --template: 从 change 描述中提取结构化元数据
  - jj diff -r: 只处理自上次蒸馏 bookmark 以来的增量变更
  - bookmark: distilled-l1 标记上次 L1 蒸馏位置
  - Change ID: 每条记忆关联到来源 change，支持溯源
"""

import hashlib
import json
import os
import subprocess
from pathlib import Path
from datetime import datetime

VAULT = Path(os.environ.get("CI_PROJECT_DIR", "."))
OUTPUT = VAULT / "distilled" / "L1" / datetime.now().strftime("%F")
OUTPUT.mkdir(parents=True, exist_ok=True)


def jj_cmd(*args) -> str:
    """执行 jj 命令并返回输出"""
    result = subprocess.run(
        ["jj"] + list(args),
        cwd=VAULT, capture_output=True, text=True
    )
    return result.stdout.strip()


def jj_get_harvest_changes() -> list[dict]:
    """用 jj log 提取自上次 L1 蒸馏以来的所有 harvest change 元数据

    jj 特性: jj log --template 从 change 描述中结构化提取
    jj 特性: bookmark 标记蒸馏进度
    """
    # 检查 distilled-l1 bookmark 是否存在
    bookmarks = jj_cmd("bookmark", "list")
    if "distilled-l1:" in bookmarks:
        rev_range = "distilled-l1..@"
    else:
        rev_range = "root()..@"

    # 提取所有 harvest 类型的 change
    raw = jj_cmd(
        "log", "-r", rev_range, "--no-graph",
        "-T", 'if(description.contains("type: harvest"), '
              'change_id ++ "|" ++ description.first_line() ++ "\\n")'
    )

    changes = []
    for line in raw.splitlines():
        if "|" not in line:
            continue
        change_id, first_line = line.split("|", 1)
        changes.append({
            "change_id": change_id.strip(),
            "description": first_line.strip(),
        })
    return changes


def jj_get_changed_files(change_id: str) -> list[str]:
    """用 jj diff 获取某个 change 中变更的文件列表

    jj 特性: jj diff -r <change_id> 精确查看某个 change 的变更
    """
    raw = jj_cmd("diff", "-r", change_id, "--name-only")
    return [f for f in raw.splitlines() if f.strip()]


def parse_claude_memory(filepath: Path, change_id: str = "") -> list[dict]:
    text = filepath.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return [{"source": "claude", "type": "unknown",
                 "content": text.strip(), "machine": filepath.parent.name,
                 "change_id": change_id}]
    parts = text.split("---", 2)
    meta = {}
    for line in parts[1].splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip().strip("'\"")
    return [{
        "source": "claude",
        "type": meta.get("type", "unknown"),
        "name": meta.get("name", filepath.stem),
        "content": parts[2].strip() if len(parts) > 2 else "",
        "machine": filepath.parent.name,
        "change_id": change_id,
    }]


def parse_gemini_memory(filepath: Path, change_id: str = "") -> list[dict]:
    text = filepath.read_text(encoding="utf-8")
    memories = []
    in_section = False
    for line in text.splitlines():
        if "## Gemini Added Memories" in line:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section and line.strip().startswith("- "):
            memories.append({
                "source": "gemini",
                "type": "fact",
                "content": line.strip()[2:],
                "machine": filepath.parent.name,
                "change_id": change_id,
            })
    return memories


def parse_antigravity(filepath: Path, change_id: str = "") -> list[dict]:
    text = filepath.read_text(encoding="utf-8").strip()
    if not text:
        return []
    parts = filepath.relative_to(VAULT / "raw" / "antigravity").parts
    machine = parts[0] if len(parts) > 0 else "unknown"
    project = parts[1] if len(parts) > 1 else "unknown"
    return [{
        "source": "antigravity",
        "type": "knowledge",
        "content": text,
        "machine": machine,
        "project": project,
        "change_id": change_id,
    }]


def parse_openclaw(filepath: Path, change_id: str = "") -> list[dict]:
    text = filepath.read_text(encoding="utf-8").strip()
    if not text:
        return []
    is_daily = filepath.parent.name == "daily"
    return [{
        "source": "openclaw",
        "type": "daily" if is_daily else "long-term",
        "content": text,
        "date": filepath.stem if is_daily else None,
        "change_id": change_id,
    }]


def parse_codex(filepath: Path, change_id: str = "") -> list[dict]:
    text = filepath.read_text(encoding="utf-8").strip()
    if not text:
        return []
    return [{
        "source": "codex",
        "type": "instruction",
        "content": text,
        "machine": filepath.parent.name,
        "change_id": change_id,
    }]


PARSERS = {
    "raw/claude": parse_claude_memory,
    "raw/gemini": parse_gemini_memory,
    "raw/antigravity": parse_antigravity,
    "raw/openclaw": parse_openclaw,
    "raw/codex": parse_codex,
}


def collect_incremental() -> list[dict]:
    """增量收集: 只处理自上次 L1 蒸馏以来新增/变更的记忆

    jj 特性: 通过 change 元数据 + diff 精确识别增量
    """
    changes = jj_get_harvest_changes()
    all_memories = []

    if not changes:
        print("No new harvest changes since last L1, falling back to full scan")
        return collect_full()

    for change in changes:
        change_id = change["change_id"]
        files = jj_get_changed_files(change_id)

        for fpath in files:
            full_path = VAULT / fpath
            if not full_path.exists() or not full_path.is_file():
                continue

            for prefix, parser in PARSERS.items():
                if fpath.startswith(prefix):
                    all_memories.extend(parser(full_path, change_id))
                    break

    print(f"Incremental: {len(changes)} harvest changes → "
          f"{len(all_memories)} memory entries")
    return all_memories


def collect_full() -> list[dict]:
    """全量收集: 扫描所有 raw/ 目录"""
    all_memories = []
    raw = VAULT / "raw"

    for f in (raw / "claude").rglob("*.md"):
        all_memories.extend(parse_claude_memory(f))
    for f in (raw / "gemini").rglob("GEMINI.md"):
        all_memories.extend(parse_gemini_memory(f))
    for f in (raw / "antigravity").rglob("*"):
        if f.is_file() and f.suffix in (".md", ".txt", ".json"):
            all_memories.extend(parse_antigravity(f))
    for f in (raw / "openclaw").rglob("*.md"):
        all_memories.extend(parse_openclaw(f))
    for f in (raw / "codex").rglob("AGENTS.md"):
        all_memories.extend(parse_codex(f))

    return all_memories


def collect_l0_output() -> list[dict]:
    """收集 L0 对话蒸馏的输出，合并到 L1 输入中"""
    l0_memories = []
    l0_dir = VAULT / "distilled" / "L0"

    # 找所有 _l0_merged.json
    for merged in l0_dir.rglob("_l0_merged.json"):
        try:
            entries = json.loads(merged.read_text(encoding="utf-8"))
            for entry in entries:
                if not isinstance(entry, dict) or not entry.get("content"):
                    continue
                l0_memories.append({
                    "source": entry.get("source", "unknown"),
                    "type": entry.get("type", "knowledge"),
                    "content": entry["content"],
                    "machine": entry.get("machine", "unknown"),
                    "project": entry.get("project", "global"),
                    "context": entry.get("context", ""),
                    "origin": "conversation",
                    "change_id": "",
                })
        except (json.JSONDecodeError, KeyError):
            pass

    if l0_memories:
        print(f"L0 input: {len(l0_memories)} entries from conversation distillation")
    return l0_memories


def dedup(memories: list[dict]) -> list[dict]:
    seen = set()
    unique = []
    for m in memories:
        h = hashlib.md5(m["content"].strip()[:500].encode()).hexdigest()
        if h not in seen:
            seen.add(h)
            unique.append(m)
    return unique


def group_by_project(memories: list[dict]) -> dict[str, list[dict]]:
    grouped = {}
    for m in memories:
        proj = m.get("project", "global")
        grouped.setdefault(proj, []).append(m)
    return grouped


def main():
    # 优先增量，fallback 全量
    all_memories = collect_incremental()

    # 合并 L0 对话蒸馏的输出
    l0_memories = collect_l0_output()
    all_memories.extend(l0_memories)

    unique = dedup(all_memories)
    by_project = group_by_project(unique)

    # 记录本次处理的 harvest change IDs (供 L2 追溯)
    harvest_ids = list({m.get("change_id", "") for m in unique if m.get("change_id")})

    for proj, mems in by_project.items():
        outfile = OUTPUT / f"{proj}.json"
        with open(outfile, "w", encoding="utf-8") as f:
            json.dump(mems, f, ensure_ascii=False, indent=2)

    # 写入元数据供后续阶段使用
    meta = {
        "date": datetime.now().isoformat(),
        "raw_count": len(all_memories),
        "unique_count": len(unique),
        "projects": list(by_project.keys()),
        "harvest_change_ids": harvest_ids,
    }
    with open(OUTPUT / "_meta.json", "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    print(f"L1 complete: {len(all_memories)} raw → {len(unique)} unique, "
          f"{len(by_project)} projects, {len(harvest_ids)} harvest changes")


if __name__ == "__main__":
    main()
