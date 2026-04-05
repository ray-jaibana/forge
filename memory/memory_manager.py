#!/usr/bin/env python3.13
"""
memory_manager.py — FORGE Bounded Memory

Manages three bounded memory files (Hermes pattern):
  MEMORY.md  — agent's personal notes (env facts, lessons, conventions)
  USER.md    — Alvaro's preferences, communication style, expectations
  PROJECT.md — active project context (stack, decisions, patterns)

These are injected into every session via context_builder.py.
The agent auto-manages them — add, replace, remove entries.

Usage:
    python memory/memory_manager.py show
    python memory/memory_manager.py show memory
    python memory/memory_manager.py add memory "Vizflow uses Prisma — never raw SQL"
    python memory/memory_manager.py add user "Alvaro prefers bullet summaries"
    python memory/memory_manager.py replace memory "old substring" "new full entry"
    python memory/memory_manager.py remove memory "stale entry substring"
    python memory/memory_manager.py render          # print system prompt block
"""

import sys
import os
from pathlib import Path
from datetime import datetime

FORGE_ROOT = Path(__file__).parent.parent
MEMORY_DIR = FORGE_ROOT / "memory"

LIMITS = {
    "memory":  2200,
    "user":    800,
    "project": 1500,
}

FILES = {
    "memory":  MEMORY_DIR / "MEMORY.md",
    "user":    MEMORY_DIR / "USER.md",
    "project": MEMORY_DIR / "PROJECT.md",
}

ENTRY_SEP = "\n§\n"

DEFAULTS = {
    "memory": "# FORGE Agent Memory\n# Personal notes — environment facts, conventions, lessons learned\n# Limit: 2,200 chars. Agent auto-manages this file.\n",
    "user":   "# User Profile — Alvaro Sanint\n# Preferences, communication style, expectations\n# Limit: 800 chars. Agent auto-manages this file.\nAlvaro prefers concise bullet summaries over long paragraphs.\nAlvaro's timezone: US Eastern (Atlanta). Primary language: English.\nAlvaro's goal: financial freedom in ≤5 years via SaaS + investments.\n",
    "project": "# Active Project Context\n# Current project: SiteTrakr (asanint/vizflow)\n# Stack: Next.js, TypeScript, Prisma, PostgreSQL, Tailwind\n# Local path: /Users/raybot/dev/git/vizflow\n# Test URL: http://localhost:3333\n# Prod URL: https://sitetrakr.com\n",
}


class MemoryManager:
    def __init__(self):
        MEMORY_DIR.mkdir(parents=True, exist_ok=True)
        self._ensure_files()

    def _ensure_files(self):
        for key, path in FILES.items():
            if not path.exists():
                path.write_text(DEFAULTS[key])

    def _read(self, target: str) -> str:
        return FILES[target].read_text()

    def _write(self, target: str, content: str):
        limit = LIMITS[target]
        if len(content) > limit:
            raise ValueError(f"{target} memory is over limit ({len(content)}/{limit} chars). Remove entries first.")
        FILES[target].write_text(content)

    def _parse_entries(self, content: str) -> list[str]:
        """Split content into header + entries."""
        lines = content.split("\n")
        header_lines = []
        entry_lines = []
        in_header = True
        for line in lines:
            if in_header and line.startswith("#"):
                header_lines.append(line)
            else:
                in_header = False
                entry_lines.append(line)
        header = "\n".join(header_lines).strip()
        body = "\n".join(entry_lines).strip()
        entries = [e.strip() for e in body.split("§") if e.strip()]
        return header, entries

    def add(self, target: str, entry: str) -> bool:
        """Add a new entry. Returns True on success."""
        if target not in FILES:
            raise ValueError(f"Unknown target: {target}. Use: memory, user, project")
        content = self._read(target)
        header, entries = self._parse_entries(content)
        entries.append(entry.strip())
        new_content = header + "\n" + ENTRY_SEP.join(entries) + "\n"
        self._write(target, new_content)
        return True

    def replace(self, target: str, old_substring: str, new_entry: str) -> bool:
        """Replace an entry containing old_substring with new_entry."""
        if target not in FILES:
            raise ValueError(f"Unknown target: {target}")
        content = self._read(target)
        header, entries = self._parse_entries(content)
        matches = [i for i, e in enumerate(entries) if old_substring in e]
        if len(matches) == 0:
            raise ValueError(f"No entry found containing: '{old_substring}'")
        if len(matches) > 1:
            raise ValueError(f"Ambiguous match — {len(matches)} entries contain '{old_substring}'. Use a more specific substring.")
        entries[matches[0]] = new_entry.strip()
        new_content = header + "\n" + ENTRY_SEP.join(entries) + "\n"
        self._write(target, new_content)
        return True

    def remove(self, target: str, old_substring: str) -> bool:
        """Remove an entry containing old_substring."""
        if target not in FILES:
            raise ValueError(f"Unknown target: {target}")
        content = self._read(target)
        header, entries = self._parse_entries(content)
        matches = [i for i, e in enumerate(entries) if old_substring in e]
        if len(matches) == 0:
            raise ValueError(f"No entry found containing: '{old_substring}'")
        if len(matches) > 1:
            raise ValueError(f"Ambiguous match — {len(matches)} entries contain '{old_substring}'.")
        entries.pop(matches[0])
        new_content = header + "\n" + ENTRY_SEP.join(entries) + "\n"
        self._write(target, new_content)
        return True

    def show(self, target: str = None) -> str:
        """Show current memory contents."""
        if target:
            if target not in FILES:
                raise ValueError(f"Unknown target: {target}")
            content = self._read(target)
            limit = LIMITS[target]
            used = len(content)
            pct = round(used / limit * 100)
            return f"[{target.upper()} — {pct}% full — {used}/{limit} chars]\n\n{content}"
        else:
            parts = []
            for t in ["memory", "user", "project"]:
                content = self._read(t)
                limit = LIMITS[t]
                used = len(content)
                pct = round(used / limit * 100)
                parts.append(f"[{t.upper()} — {pct}% full — {used}/{limit} chars]\n{content}")
            return "\n" + ("─" * 50) + "\n".join(parts)

    def render(self) -> str:
        """Render the full memory block for system prompt injection."""
        sep = "═" * 38
        lines = [sep, "FORGE MEMORY", sep]

        for t in ["memory", "user", "project"]:
            content = self._read(t)
            limit = LIMITS[t]
            used = len(content)
            pct = round(used / limit * 100)
            header, entries = self._parse_entries(content)
            label = {"memory": "AGENT MEMORY", "user": "USER PROFILE", "project": "PROJECT"}[t]
            lines.append(f"\n[{label} — {pct}% — {used}/{limit} chars]")
            for e in entries:
                if e:
                    lines.append(e)

        # Recent sessions snippet
        try:
            from memory.sessiondb import SessionDB
            db = SessionDB()
            recent = db.recent_sessions(limit=3)
            if recent:
                lines.append("\n[RECENT SESSIONS — last 3]")
                for s in recent:
                    ts = s["started_at"][:10]
                    summary = (s["summary"] or "no summary")[:80]
                    lines.append(f"{ts} {s['agent']}: {summary}")
        except Exception:
            pass  # sessiondb not required for memory render

        lines.append(sep)
        return "\n".join(lines)

    def usage(self) -> dict:
        result = {}
        for t in ["memory", "user", "project"]:
            content = self._read(t)
            limit = LIMITS[t]
            used = len(content)
            result[t] = {"used": used, "limit": limit, "pct": round(used / limit * 100)}
        return result


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)

    mm = MemoryManager()
    cmd = args[0]
    rest = args[1:]

    try:
        if cmd == "show":
            target = rest[0] if rest else None
            print(mm.show(target))

        elif cmd == "add":
            if len(rest) < 2:
                print("Usage: add <target> <entry text>")
                sys.exit(1)
            target = rest[0]
            entry = " ".join(rest[1:])
            mm.add(target, entry)
            u = mm.usage()[target]
            print(f"✅ Added to {target} ({u['pct']}% full, {u['used']}/{u['limit']} chars)")

        elif cmd == "replace":
            if len(rest) < 3:
                print("Usage: replace <target> <old_substring> <new_entry>")
                sys.exit(1)
            target, old, new = rest[0], rest[1], " ".join(rest[2:])
            mm.replace(target, old, new)
            print(f"✅ Replaced in {target}")

        elif cmd == "remove":
            if len(rest) < 2:
                print("Usage: remove <target> <substring>")
                sys.exit(1)
            target, old = rest[0], " ".join(rest[1:])
            mm.remove(target, old)
            print(f"✅ Removed from {target}")

        elif cmd == "render":
            print(mm.render())

        elif cmd == "usage":
            for t, u in mm.usage().items():
                bar = "█" * (u["pct"] // 5) + "░" * (20 - u["pct"] // 5)
                print(f"  {t:8} [{bar}] {u['pct']:3}%  {u['used']}/{u['limit']} chars")

        else:
            print(f"Unknown command: {cmd}")
            print("Commands: show, add, replace, remove, render, usage")
            sys.exit(1)

    except ValueError as e:
        print(f"❌ {e}")
        sys.exit(1)
