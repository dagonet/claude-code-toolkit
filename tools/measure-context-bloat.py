#!/usr/bin/env python3
"""Measure context bloat across Claude Code session JSONL files.

Parses existing session logs and buckets content blocks by source, then emits
a markdown report. Data-only — no recommendations. See
docs/plans/2026-04-13-workflow-meta-issues.md addendum for the design spec.
"""

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(
        description="Measure context bloat in Claude Code sessions"
    )
    p.add_argument("--top-n", type=int, default=10)
    p.add_argument("--project-filter", type=str, default="claude-code-toolkit")
    return p.parse_args()


def find_sessions(project_filter: str):
    root = Path.home() / ".claude" / "projects"
    if not root.is_dir():
        return []
    cutoff_ts = (datetime.now() - timedelta(days=30)).timestamp()
    matches = []
    for jsonl in root.glob("*/*.jsonl"):
        try:
            st = jsonl.stat()
        except OSError:
            continue
        if st.st_size < 500 * 1024:
            continue
        if st.st_mtime < cutoff_ts:
            continue
        if project_filter and project_filter not in str(jsonl).lower():
            continue
        matches.append((jsonl, st.st_size))
    matches.sort(key=lambda t: t[1], reverse=True)
    return matches


def iter_messages(path: Path):
    """Yield parsed messages, skipping unparseable lines (truncated tail)."""
    try:
        with path.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
    except OSError:
        return


def extract_blocks(message):
    """Return (role, content_blocks) for a JSONL message record."""
    if not isinstance(message, dict):
        return None, []
    msg = message.get("message") or {}
    role = msg.get("role") or message.get("role")
    content = msg.get("content")
    if content is None:
        content = message.get("content")
    if content is None:
        return role, []
    if isinstance(content, str):
        return role, [{"type": "text", "text": content}]
    if isinstance(content, list):
        return role, content
    return role, []


def extract_usage(message):
    if not isinstance(message, dict):
        return None
    msg = message.get("message") or {}
    usage = msg.get("usage") or message.get("usage")
    return usage if isinstance(usage, dict) else None


def block_text(block) -> str:
    """Flatten a block's text content for string matching."""
    if not isinstance(block, dict):
        return ""
    t = block.get("type")
    if t == "text":
        return block.get("text") or ""
    if t == "tool_result":
        content = block.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    parts.append(c.get("text") or "")
                elif isinstance(c, str):
                    parts.append(c)
            return " ".join(parts)
    return ""


def is_skill_content(block) -> bool:
    text = block_text(block)
    if not text:
        return False
    if "Base directory for this skill" in text:
        return True
    if "<system-reminder>" in text and "---\nname:" in text:
        return True
    return False


def bucket_for_tool_result(tool_name: str, tool_input: dict) -> str:
    if tool_name == "Read":
        fp = (tool_input.get("file_path") or "").lower()
        if fp.endswith("claude.md"):
            return "claude_md"
        if fp.endswith("agent_team.md"):
            return "agent_team_md"
    if tool_name == "Skill":
        return "skill_content"
    if tool_name in ("Agent", "Task"):
        return "subagent_result"
    return f"tool_result:{tool_name or 'unknown'}"


def block_chars(block) -> int:
    try:
        return len(json.dumps(block, ensure_ascii=False))
    except (TypeError, ValueError):
        return len(str(block))


def process_session(path: Path):
    """Two-pass bucket + peak-token + message-count walk. Returns a dict."""
    tool_uses = {}
    msg_count = 0

    # Pass 1 — build tool_use_id → {name, input} map.
    for msg in iter_messages(path):
        msg_count += 1
        _, blocks = extract_blocks(msg)
        for block in blocks:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                tuid = block.get("id")
                if tuid:
                    tool_uses[tuid] = {
                        "name": block.get("name") or "",
                        "input": block.get("input") or {},
                    }

    # Pass 2 — bucket every content block + compute peak tokens.
    buckets = Counter()
    peak = 0
    for msg in iter_messages(path):
        usage = extract_usage(msg)
        if usage:
            total = (
                int(usage.get("input_tokens") or 0)
                + int(usage.get("cache_read_input_tokens") or 0)
                + int(usage.get("cache_creation_input_tokens") or 0)
            )
            if total > peak:
                peak = total

        role, blocks = extract_blocks(msg)
        for block in blocks:
            if not isinstance(block, dict):
                continue
            chars = block_chars(block)
            btype = block.get("type")

            if btype == "tool_result":
                tu = tool_uses.get(block.get("tool_use_id")) or {}
                name = tu.get("name", "")
                tinput = tu.get("input", {}) or {}
                bucket = bucket_for_tool_result(name, tinput)
                if bucket not in ("claude_md", "agent_team_md") and is_skill_content(block):
                    bucket = "skill_content"
                buckets[bucket] += chars
                continue

            if btype == "tool_use":
                buckets["assistant_tool_use"] += chars
                continue

            if btype == "thinking":
                buckets["assistant_thinking"] += chars
                continue

            if btype == "text":
                if is_skill_content(block):
                    buckets["skill_content"] += chars
                elif role == "assistant":
                    buckets["assistant_text"] += chars
                elif role == "user":
                    text = block.get("text") or ""
                    if "<system-reminder>" in text:
                        buckets["user_system_reminder"] += chars
                    else:
                        buckets["user_text"] += chars
                else:
                    buckets["unknown"] += chars
                continue

            buckets["unknown"] += chars

    return {
        "buckets": buckets,
        "peak": peak,
        "msgs": msg_count,
    }


def fmt_mb(n: int) -> str:
    return f"{n / (1024 * 1024):.1f}"


def fmt_pct(part: int, total: int) -> str:
    if total <= 0:
        return "0.0%"
    return f"{100 * part / total:.1f}%"


def emit_report(sessions_data, top_n_requested: int):
    today = datetime.now().strftime("%Y-%m-%d")
    n = len(sessions_data)
    out = []
    out.append(f"# Context Bloat Baseline — {today}")
    out.append("")
    out.append("(token counts are approximate: tokens ≈ chars / 4)")
    out.append("")

    out.append(f"## Top {n} sessions by file size")
    out.append("")
    out.append(
        "| rank | project | session | size_MB | msgs | peak_input_tokens | sum_bucket_chars |"
    )
    out.append("|---|---|---|---|---|---|---|")
    for i, d in enumerate(sessions_data, 1):
        sum_chars = sum(d["buckets"].values())
        out.append(
            f"| {i} | {d['project']} | {d['session']} | {fmt_mb(d['size'])} | "
            f"{d['msgs']} | {d['peak']} | {sum_chars} |"
        )
    out.append("")

    agg = Counter()
    for d in sessions_data:
        agg.update(d["buckets"])
    total = sum(agg.values())
    out.append(f"## Aggregated buckets across top {n} (totals)")
    out.append("")
    out.append("| bucket | chars | % of total |")
    out.append("|---|---|---|")
    for bucket, chars in agg.most_common():
        out.append(f"| {bucket} | {chars} | {fmt_pct(chars, total)} |")
    out.append("")

    out.append("## Per-session detail (top 3 by size)")
    out.append("")
    for i, d in enumerate(sessions_data[:3], 1):
        sum_chars = sum(d["buckets"].values())
        out.append(
            f"### {i}. {d['project']} / {d['session']} — "
            f"{fmt_mb(d['size'])} MB, peak {d['peak']} tokens"
        )
        out.append("")
        out.append("| bucket | chars | % |")
        out.append("|---|---|---|")
        for bucket, chars in d["buckets"].most_common():
            out.append(f"| {bucket} | {chars} | {fmt_pct(chars, sum_chars)} |")
        out.append("")

    print("\n".join(out))


def main():
    args = parse_args()
    pf = args.project_filter.lower() if args.project_filter else ""
    sessions = find_sessions(pf)[: args.top_n]
    if not sessions:
        print("No sessions matched filter.", file=sys.stderr)
        return 1

    data = []
    for jsonl, size in sessions:
        result = process_session(jsonl)
        data.append({
            "project": jsonl.parent.name,
            "session": jsonl.stem[:8],
            "size": size,
            "msgs": result["msgs"],
            "peak": result["peak"],
            "buckets": result["buckets"],
        })

    emit_report(data, args.top_n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
