#!/usr/bin/env python3
"""
context_builder.py — FORGE Context Assembly

Assembles the memory block injected at session start.
Called by CLAUDE.md via @memory/context_builder.py or bash.

Usage:
    python memory/context_builder.py           # print context block
    python memory/context_builder.py --agent atlas
    python memory/context_builder.py --json    # machine-readable output
"""

import sys
import json
from pathlib import Path
from datetime import datetime

FORGE_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(FORGE_ROOT))


def build_context(agent: str = None) -> str:
    sep = "═" * 42
    lines = [sep, f"  FORGE MEMORY  {('— ' + agent) if agent else ''}", sep, ""]

    # Memory files
    try:
        from memory.memory_manager import MemoryManager
        mm = MemoryManager()
        lines.append(mm.render())
    except Exception as e:
        lines.append(f"[Memory unavailable: {e}]")

    lines.append("")

    # Recent sessions
    try:
        from memory.sessiondb import SessionDB
        db = SessionDB()
        recent = db.recent_sessions(agent=agent, limit=5)
        if recent:
            lines.append("[RECENT SESSIONS]")
            for s in recent:
                ts = s["started_at"][:10]
                turns = s["turn_count"]
                summary = (s["summary"] or "(no summary)")[:90]
                lines.append(f"  {ts} [{s['agent']:8}] {turns:2} turns  {summary}")
        else:
            lines.append("[RECENT SESSIONS: none yet]")
    except Exception as e:
        lines.append(f"[Sessions unavailable: {e}]")

    lines.append("")

    # Pending skill evaluations
    try:
        from memory.skill_trigger import SkillTrigger, PENDING_FILE
        if PENDING_FILE.exists():
            trigger = SkillTrigger()
            pending = trigger.list_pending()
            if pending:
                lines.append(f"[PENDING SKILL EVALUATIONS: {len(pending)} sessions queued]")
                lines.append("  Run: python memory/skill_trigger.py run-pending")
    except Exception:
        pass

    lines.append(sep)
    return "\n".join(lines)


def build_context_json(agent: str = None) -> dict:
    result = {"agent": agent, "timestamp": datetime.utcnow().isoformat()}

    # Memory
    try:
        from memory.memory_manager import MemoryManager
        mm = MemoryManager()
        result["memory"] = mm.usage()
        result["memory_content"] = {
            t: (FORGE_ROOT / "memory" / f"{t.upper()}.md").read_text()
            for t in ["memory", "user", "project"]
            if (FORGE_ROOT / "memory" / f"{t.upper()}.md").exists()
        }
    except Exception as e:
        result["memory_error"] = str(e)

    # Sessions
    try:
        from memory.sessiondb import SessionDB
        db = SessionDB()
        result["recent_sessions"] = db.recent_sessions(agent=agent, limit=5)
        result["stats"] = db.stats()
    except Exception as e:
        result["sessions_error"] = str(e)

    return result


if __name__ == "__main__":
    args = sys.argv[1:]
    agent = None
    as_json = False

    i = 0
    while i < len(args):
        if args[i] == "--agent" and i + 1 < len(args):
            agent = args[i + 1]; i += 2
        elif args[i] == "--json":
            as_json = True; i += 1
        else:
            i += 1

    if as_json:
        print(json.dumps(build_context_json(agent), indent=2, default=str))
    else:
        print(build_context(agent))
