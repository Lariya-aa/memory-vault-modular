#!/usr/bin/env python3
"""L0 对话蒸馏: 从 conversations/ 中提取可复用知识

支持的对话格式:
  - Claude CLI: JSONL, type=user/assistant, message.content (text parts)
  - Gemini CLI: JSON, type=user/gemini, content (text parts)
  - Codex CLI:  JSONL, role=user/assistant (未来支持)

输出: distilled/L0/{date}/{tool}-{machine}-{session}.md
      每个对话提取为一个简洁的 Markdown 摘要，供 L1 消费

不使用 LLM — 纯结构化提取。LLM 蒸馏在 L0-distill.sh 中完成。
"""

import json
import os
import hashlib
from pathlib import Path
from datetime import datetime

# 单个对话提取的最大用户消息数 (防止超长对话撑爆 Gemini context)
MAX_TURNS = 40
# 单条消息最大字符数
MAX_MSG_LEN = 800


def extract_claude_session(filepath: Path) -> dict | None:
    """解析 Claude CLI JSONL 对话

    格式:
      每行一个 JSON 对象
      type=user: message.content (str 或 list[{type:text, text:...}])
      type=assistant: message.content (list[{type:text, text:...}, {type:thinking, ...}])
    """
    turns = []
    session_id = filepath.stem
    project = ""

    with open(filepath, encoding="utf-8") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type", "")
            if not project and obj.get("cwd"):
                project = Path(obj["cwd"]).name

            if msg_type not in ("user", "assistant"):
                continue

            message = obj.get("message", {})
            content = message.get("content", "")
            text = ""

            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text_parts = []
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        text_parts.append(part.get("text", ""))
                text = "\n".join(text_parts)

            # 跳过空消息和系统消息
            if not text.strip() or text.startswith("<local-command"):
                continue

            role = "user" if msg_type == "user" else "assistant"
            turns.append({
                "role": role,
                "text": text[:MAX_MSG_LEN],
            })

    if not turns:
        return None

    # 只保留最后 MAX_TURNS 轮
    if len(turns) > MAX_TURNS:
        turns = turns[-MAX_TURNS:]

    return {
        "tool": "claude",
        "session_id": session_id,
        "project": project,
        "turn_count": len(turns),
        "turns": turns,
    }


def extract_gemini_session(filepath: Path) -> dict | None:
    """解析 Gemini CLI JSON 对话

    格式:
      {sessionId, messages: [{type: user/gemini, content: [{text:...}]}]}
    """
    try:
        data = json.load(open(filepath, encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None

    messages = data.get("messages", [])
    session_id = data.get("sessionId", filepath.stem)
    project_hash = data.get("projectHash", "")
    turns = []

    for msg in messages:
        msg_type = msg.get("type", "")
        if msg_type not in ("user", "gemini"):
            continue

        content = msg.get("content", [])
        text = ""
        if isinstance(content, list):
            text_parts = []
            for part in content:
                if isinstance(part, dict) and "text" in part:
                    text_parts.append(part["text"])
                elif isinstance(part, str):
                    text_parts.append(part)
            text = "\n".join(text_parts)
        elif isinstance(content, str):
            text = content

        if not text.strip():
            continue

        role = "user" if msg_type == "user" else "assistant"
        turns.append({
            "role": role,
            "text": text[:MAX_MSG_LEN],
        })

    if not turns:
        return None

    if len(turns) > MAX_TURNS:
        turns = turns[-MAX_TURNS:]

    return {
        "tool": "gemini",
        "session_id": session_id,
        "project": project_hash,
        "turn_count": len(turns),
        "turns": turns,
    }


def extract_codex_session(filepath: Path) -> dict | None:
    """解析 Codex CLI JSONL 对话

    格式 (与 Claude 类似):
      每行一个 JSON, role=user/assistant, content=str
    """
    turns = []
    session_id = filepath.stem

    with open(filepath, encoding="utf-8") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            role = obj.get("role", "")
            if role not in ("user", "assistant"):
                continue

            content = obj.get("content", "")
            text = ""
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text_parts = []
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        text_parts.append(part.get("text", ""))
                text = "\n".join(text_parts)

            if not text.strip():
                continue

            turns.append({
                "role": role,
                "text": text[:MAX_MSG_LEN],
            })

    if not turns:
        return None

    if len(turns) > MAX_TURNS:
        turns = turns[-MAX_TURNS:]

    return {
        "tool": "codex",
        "session_id": session_id,
        "project": "",
        "turn_count": len(turns),
        "turns": turns,
    }


def extract_antigravity_brain(brain_dir: Path) -> list[dict]:
    """从 raw/antigravity/{machine}/_global/brain/ 中提取 Antigravity 对话产出

    每个子目录是一个 conversation UUID,包含 task.md, implementation_plan.md, walkthrough.md 等
    """
    sessions = []
    if not brain_dir.exists():
        return sessions

    for conv_dir in sorted(brain_dir.iterdir()):
        if not conv_dir.is_dir():
            continue

        conv_id = conv_dir.name
        turns = []

        # 读取所有 markdown 文件作为 "AI 产出"
        md_files = sorted(conv_dir.glob("*.md"))
        for md_file in md_files:
            # 跳过 .resolved 文件
            if ".resolved" in md_file.name:
                continue
            try:
                text = md_file.read_text(encoding="utf-8")[:MAX_MSG_LEN * 3]
            except (UnicodeDecodeError, OSError):
                continue
            if not text.strip():
                continue

            turns.append({
                "role": "assistant",
                "text": f"[{md_file.stem}]\n{text[:MAX_MSG_LEN]}",
            })

        # 读取 metadata json 获取上下文
        for meta_file in conv_dir.glob("*.metadata.json"):
            try:
                meta = json.load(open(meta_file, encoding="utf-8"))
                summary = meta.get("Summary", meta.get("summary", ""))
                if summary:
                    turns.insert(0, {
                        "role": "user",
                        "text": f"[context] {summary[:MAX_MSG_LEN]}",
                    })
            except (json.JSONDecodeError, OSError):
                continue

        if len(turns) >= 1:
            sessions.append({
                "tool": "antigravity",
                "session_id": conv_id,
                "project": "",
                "turn_count": len(turns),
                "turns": turns,
            })

    return sessions


def extract_antigravity_knowledge(knowledge_dir: Path) -> list[dict]:
    """从 raw/antigravity/{machine}/_global/knowledge/ 中提取知识库

    每个子目录是一个知识主题,包含 metadata.json + artifacts/*.md
    """
    sessions = []
    if not knowledge_dir.exists():
        return sessions

    for ki_dir in sorted(knowledge_dir.iterdir()):
        if not ki_dir.is_dir():
            continue

        ki_name = ki_dir.name
        turns = []

        # 读取 metadata.json
        meta_file = ki_dir / "metadata.json"
        title = ki_name
        if meta_file.exists():
            try:
                meta = json.load(open(meta_file, encoding="utf-8"))
                title = meta.get("title", ki_name)
                summary = meta.get("summary", "")
                keywords = meta.get("keywords", [])
                if summary:
                    turns.append({
                        "role": "user",
                        "text": f"[KI: {title}] {summary[:MAX_MSG_LEN]}",
                    })
                if keywords:
                    turns.append({
                        "role": "user",
                        "text": f"Keywords: {', '.join(keywords[:20])}",
                    })
            except (json.JSONDecodeError, OSError):
                pass

        # 读取 artifacts/*.md
        artifacts_dir = ki_dir / "artifacts"
        if artifacts_dir.exists():
            for md_file in sorted(artifacts_dir.glob("*.md")):
                try:
                    text = md_file.read_text(encoding="utf-8")
                except (UnicodeDecodeError, OSError):
                    continue
                if text.strip():
                    turns.append({
                        "role": "assistant",
                        "text": f"[{md_file.stem}]\n{text[:MAX_MSG_LEN]}",
                    })

        if turns:
            sessions.append({
                "tool": "antigravity",
                "session_id": f"ki-{ki_name}",
                "project": "",
                "turn_count": len(turns),
                "turns": turns,
            })

    return sessions


def format_for_distillation(session: dict) -> str:
    """将对话格式化为 Gemini CLI 可蒸馏的 Markdown"""
    lines = []
    lines.append(f"# {session['tool']} session: {session['session_id'][:12]}")
    lines.append(f"Project: {session.get('project', 'unknown')}")
    lines.append(f"Turns: {session['turn_count']}")
    lines.append("")

    for turn in session["turns"]:
        prefix = "**User:**" if turn["role"] == "user" else "**AI:**"
        lines.append(f"{prefix} {turn['text']}")
        lines.append("")

    return "\n".join(lines)


def dedup_key(session: dict) -> str:
    """生成去重 key: 基于前3条用户消息的 hash"""
    user_texts = [t["text"][:200] for t in session["turns"] if t["role"] == "user"][:3]
    return hashlib.md5("".join(user_texts).encode()).hexdigest()


def _is_valid_session(session: dict) -> bool:
    """过滤掉过短/纯工具调用的无意义对话"""
    if not session or "turns" not in session:
        return False

    turn_count = len(session.get("turns", []))
    if turn_count < 4:
        return False

    user_texts = [t["text"] for t in session["turns"] if t.get("role") == "user"]
    if not user_texts:
        return False

    avg_user_len = sum(len(t) for t in user_texts) / max(len(user_texts), 1)
    if avg_user_len < 20:
        return False

    return True


def main():
    VAULT_ROOT = Path(os.environ.get("CI_PROJECT_DIR", os.environ.get("MEMORY_VAULT", ".")))
    CONV_DIR = VAULT_ROOT / "conversations"
    RAW_DIR = VAULT_ROOT / "raw"
    OUTPUT = VAULT_ROOT / "distilled" / "L0" / datetime.now().strftime("%F")
    OUTPUT.mkdir(parents=True, exist_ok=True)

    sessions = []
    seen_keys = set()
    
    # 增量优化：获取所有已经成功蒸馏过的会话 ID，避免流水线重复消耗 Token
    distilled_sids = set()
    l0_base_dir = VAULT_ROOT / "distilled" / "L0"
    if l0_base_dir.exists():
        for f in l0_base_dir.rglob("_distilled/*.json"):
            distilled_sids.add(f.stem)  # 格式为: {tool}-{machine}-{sid}

    # 遍历所有 conversations/ 下的文件
    for tool_dir in sorted(CONV_DIR.iterdir()) if CONV_DIR.exists() else []:
        if not tool_dir.is_dir():
            continue
        tool_name = tool_dir.name  # claude / gemini / codex

        for filepath in tool_dir.rglob("*"):
            if not filepath.is_file():
                continue

            session = None
            if tool_name == "claude" and filepath.suffix == ".jsonl":
                session = extract_claude_session(filepath)
            elif tool_name == "gemini" and filepath.suffix == ".json":
                session = extract_gemini_session(filepath)
            elif tool_name == "codex" and filepath.suffix == ".jsonl":
                session = extract_codex_session(filepath)

            if session and _is_valid_session(session):
                # 从路径提取机器名
                # conversations/{tool}/{machine}/{date}/{file}
                parts = filepath.relative_to(CONV_DIR).parts
                machine = parts[1] if len(parts) > 1 else "unknown"
                session["machine"] = machine

                # 检查是否已经被蒸馏过
                sid = session["session_id"][:12]
                export_name = f"{tool_name}-{machine}-{sid}"
                if export_name in distilled_sids:
                    continue

                # 去重
                key = dedup_key(session)
                if key not in seen_keys:
                    seen_keys.add(key)
                    sessions.append(session)

    # Antigravity: 从 raw/ 目录提取 brain + knowledge
    if RAW_DIR.exists():
        for anti_dir in sorted(RAW_DIR.glob("antigravity/*")):
            if not anti_dir.is_dir():
                continue
            machine = anti_dir.name

            # brain 对话产出
            brain_dir = anti_dir / "_global" / "brain"
            for session in extract_antigravity_brain(brain_dir):
                session["machine"] = machine
                sid = session["session_id"][:12]
                if f"antigravity-{machine}-{sid}" in distilled_sids:
                    continue
                key = dedup_key(session)
                if key not in seen_keys:
                    seen_keys.add(key)
                    sessions.append(session)

            # knowledge 知识库
            knowledge_dir = anti_dir / "_global" / "knowledge"
            for session in extract_antigravity_knowledge(knowledge_dir):
                session["machine"] = machine
                sid = session["session_id"][:12]
                if f"antigravity-{machine}-{sid}" in distilled_sids:
                    continue
                key = dedup_key(session)
                if key not in seen_keys:
                    seen_keys.add(key)
                    sessions.append(session)

    if not sessions:
        print("L0-extract: No conversations found")
        return

    # 写出每个对话的格式化文本 (供 distill-l0.sh 用 Gemini 蒸馏)
    for session in sessions:
        tool = session["tool"]
        machine = session.get("machine", "unknown")
        sid = session["session_id"][:12]
        outfile = OUTPUT / f"{tool}-{machine}-{sid}.md"

        text = format_for_distillation(session)
        outfile.write_text(text, encoding="utf-8")

    # 写入元数据
    meta = {
        "date": datetime.now().isoformat(),
        "total_sessions": len(sessions),
        "by_tool": {},
    }
    for s in sessions:
        t = s["tool"]
        meta["by_tool"][t] = meta["by_tool"].get(t, 0) + 1

    (OUTPUT / "_meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"L0-extract: {len(sessions)} sessions "
          f"({', '.join(f'{k}={v}' for k,v in meta['by_tool'].items())})")
    print(f"Output: {OUTPUT}")


if __name__ == "__main__":
    main()
