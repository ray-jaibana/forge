#!/usr/bin/env python3.13
"""
sessiondb.py — FORGE Session Database

SQLite + FTS5 store for all agent conversation turns.
Gives Atlas and teammates cross-session recall via full-text search.

Usage:
    python memory/sessiondb.py search "auth refactor decision"
    python memory/sessiondb.py recent --agent atlas --limit 10
    python memory/sessiondb.py summary <session_id>
    python memory/sessiondb.py log <session_id> <agent> <role> <content>
    python memory/sessiondb.py stats
"""

import sqlite3
import json
import sys
import uuid
import os
from datetime import datetime, timezone
from pathlib import Path

FORGE_ROOT = Path(__file__).parent.parent
DB_PATH = FORGE_ROOT / "memory" / "forge_memory.db"


def get_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    _init_schema(conn)
    return conn


def _init_schema(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS session_meta (
            session_id  TEXT PRIMARY KEY,
            agent       TEXT NOT NULL,
            started_at  TEXT NOT NULL,
            ended_at    TEXT,
            task_id     TEXT,
            summary     TEXT,
            turn_count  INTEGER DEFAULT 0
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS session_turns USING fts5(
            session_id,
            agent,
            role,
            content,
            task_id,
            timestamp,
            tokenize="porter unicode61"
        );

        CREATE TABLE IF NOT EXISTS session_turns_meta (
            rowid       INTEGER PRIMARY KEY,
            session_id  TEXT NOT NULL,
            agent       TEXT NOT NULL,
            role        TEXT NOT NULL,
            timestamp   TEXT NOT NULL,
            task_id     TEXT
        );
    """)
    conn.commit()


class SessionDB:
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.conn = get_db()

    def new_session(self, agent: str, task_id: str = None) -> str:
        """Create a new session, return session_id."""
        session_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            "INSERT INTO session_meta (session_id, agent, started_at, task_id) VALUES (?,?,?,?)",
            (session_id, agent, now, task_id)
        )
        self.conn.commit()
        return session_id

    def log_turn(self, session_id: str, agent: str, role: str, content: str, task_id: str = None):
        """Log a single conversation turn."""
        now = datetime.now(timezone.utc).isoformat()
        # FTS5 table
        self.conn.execute(
            "INSERT INTO session_turns (session_id, agent, role, content, task_id, timestamp) VALUES (?,?,?,?,?,?)",
            (session_id, agent, role, content, task_id or "", now)
        )
        # Meta table (for filtering without FTS)
        self.conn.execute(
            "INSERT INTO session_turns_meta (session_id, agent, role, timestamp, task_id) VALUES (?,?,?,?,?)",
            (session_id, agent, role, now, task_id)
        )
        # Increment turn count
        self.conn.execute(
            "UPDATE session_meta SET turn_count = turn_count + 1 WHERE session_id = ?",
            (session_id,)
        )
        self.conn.commit()

    def end_session(self, session_id: str, summary: str = None):
        """Mark session as ended, optionally store summary."""
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            "UPDATE session_meta SET ended_at = ?, summary = ? WHERE session_id = ?",
            (now, summary, session_id)
        )
        self.conn.commit()

    def search(self, query: str, agent: str = None, limit: int = 10) -> list[dict]:
        """Full-text search across all session turns."""
        if agent:
            rows = self.conn.execute(
                """SELECT session_id, agent, role, content, task_id, timestamp,
                          snippet(session_turns, 3, '[', ']', '...', 20) as snippet,
                          rank
                   FROM session_turns
                   WHERE session_turns MATCH ? AND agent = ?
                   ORDER BY rank
                   LIMIT ?""",
                (query, agent, limit)
            ).fetchall()
        else:
            rows = self.conn.execute(
                """SELECT session_id, agent, role, content, task_id, timestamp,
                          snippet(session_turns, 3, '[', ']', '...', 20) as snippet,
                          rank
                   FROM session_turns
                   WHERE session_turns MATCH ?
                   ORDER BY rank
                   LIMIT ?""",
                (query, limit)
            ).fetchall()
        return [dict(r) for r in rows]

    def recent_sessions(self, agent: str = None, limit: int = 10) -> list[dict]:
        """Get recent sessions, optionally filtered by agent."""
        if agent:
            rows = self.conn.execute(
                "SELECT * FROM session_meta WHERE agent = ? ORDER BY started_at DESC LIMIT ?",
                (agent, limit)
            ).fetchall()
        else:
            rows = self.conn.execute(
                "SELECT * FROM session_meta ORDER BY started_at DESC LIMIT ?",
                (limit,)
            ).fetchall()
        return [dict(r) for r in rows]

    def get_session(self, session_id: str) -> dict:
        """Get session metadata."""
        row = self.conn.execute(
            "SELECT * FROM session_meta WHERE session_id = ?", (session_id,)
        ).fetchone()
        return dict(row) if row else None

    def get_turns(self, session_id: str) -> list[dict]:
        """Get all turns for a session."""
        rows = self.conn.execute(
            "SELECT agent, role, content, task_id, timestamp FROM session_turns WHERE session_id = ? ORDER BY timestamp",
            (session_id,)
        ).fetchall()
        return [dict(r) for r in rows]

    def stats(self) -> dict:
        """Database statistics."""
        total_sessions = self.conn.execute("SELECT COUNT(*) FROM session_meta").fetchone()[0]
        total_turns = self.conn.execute("SELECT COUNT(*) FROM session_turns_meta").fetchone()[0]
        agents = self.conn.execute(
            "SELECT agent, COUNT(*) as sessions FROM session_meta GROUP BY agent ORDER BY sessions DESC"
        ).fetchall()
        db_size = self.db_path.stat().st_size if self.db_path.exists() else 0
        return {
            "total_sessions": total_sessions,
            "total_turns": total_turns,
            "agents": [dict(r) for r in agents],
            "db_size_kb": round(db_size / 1024, 1)
        }


# ── CLI ────────────────────────────────────────────────────────────────────────

def cmd_search(args):
    query = " ".join(args)
    agent = None
    limit = 10
    # Parse --agent and --limit flags
    filtered = []
    i = 0
    while i < len(args):
        if args[i] == "--agent" and i + 1 < len(args):
            agent = args[i + 1]; i += 2
        elif args[i] == "--limit" and i + 1 < len(args):
            limit = int(args[i + 1]); i += 2
        else:
            filtered.append(args[i]); i += 1
    query = " ".join(filtered)

    db = SessionDB()
    results = db.search(query, agent=agent, limit=limit)
    if not results:
        print("No results found.")
        return
    print(f"\n🔍 Search results for: \"{query}\"\n")
    for r in results:
        ts = r["timestamp"][:16]
        print(f"[{ts}] [{r['agent']:8}] [{r['role']:9}] task:{r['task_id'] or '-'}")
        print(f"  {r['snippet']}")
        print()


def cmd_recent(args):
    agent = None
    limit = 10
    i = 0
    while i < len(args):
        if args[i] == "--agent" and i + 1 < len(args):
            agent = args[i + 1]; i += 2
        elif args[i] == "--limit" and i + 1 < len(args):
            limit = int(args[i + 1]); i += 2
        else:
            i += 1

    db = SessionDB()
    sessions = db.recent_sessions(agent=agent, limit=limit)
    if not sessions:
        print("No sessions found.")
        return
    print(f"\n📋 Recent sessions{' for ' + agent if agent else ''}\n")
    for s in sessions:
        ended = "running" if not s["ended_at"] else s["ended_at"][:16]
        summary = (s["summary"] or "no summary")[:80]
        print(f"[{s['started_at'][:16]}] [{s['agent']:8}] turns:{s['turn_count']:3}  {s['session_id'][:8]}...")
        print(f"  {summary}")
        print()


def cmd_log(args):
    """Log a turn: log <session_id> <agent> <role> <content>"""
    if len(args) < 4:
        print("Usage: log <session_id> <agent> <role> <content>")
        sys.exit(1)
    session_id, agent, role = args[0], args[1], args[2]
    content = " ".join(args[3:])
    db = SessionDB()
    # Ensure session exists
    if not db.get_session(session_id):
        db.conn.execute(
            "INSERT OR IGNORE INTO session_meta (session_id, agent, started_at) VALUES (?,?,?)",
            (session_id, agent, datetime.now(timezone.utc).isoformat())
        )
        db.conn.commit()
    db.log_turn(session_id, agent, role, content)
    print(f"✅ Logged turn for session {session_id[:8]}... ({agent}/{role})")


def cmd_stats(_args):
    db = SessionDB()
    s = db.stats()
    print(f"\n📊 FORGE Session DB Stats")
    print(f"  Total sessions: {s['total_sessions']}")
    print(f"  Total turns:    {s['total_turns']}")
    print(f"  DB size:        {s['db_size_kb']} KB")
    print(f"\n  Sessions by agent:")
    for a in s["agents"]:
        print(f"    {a['agent']:10} {a['sessions']} sessions")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)

    cmd = args[0]
    rest = args[1:]

    if cmd == "search":    cmd_search(rest)
    elif cmd == "recent":  cmd_recent(rest)
    elif cmd == "log":     cmd_log(rest)
    elif cmd == "stats":   cmd_stats(rest)
    else:
        print(f"Unknown command: {cmd}")
        print("Commands: search, recent, log, stats")
        sys.exit(1)
