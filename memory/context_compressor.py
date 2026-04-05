#!/usr/bin/env python3.13
"""
context_compressor.py — FORGE Context Compression

Implements Hermes dual-compression pattern for long sessions:
  1. Prune old tool outputs (cheap, no LLM call)
  2. Summarize middle turns using claude --print (Max subscription)

Run manually when sessions get long, or automatically via the daemon.

Usage:
    python memory/context_compressor.py compress <session_id>
    python memory/context_compressor.py status <session_id>
    python memory/context_compressor.py prune-tools <session_id>
"""

import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime, timezone

FORGE_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(FORGE_ROOT))

# Compression triggers at this fraction of rough context budget
COMPRESSION_THRESHOLD = 0.60   # 60% of estimated context
TARGET_TAIL_RATIO = 0.20        # Keep last 20% of threshold as live tail
PROTECT_LAST_N = 15             # Always keep last N turns uncompressed
PROTECT_FIRST_N = 3             # Always keep first N turns (system + first exchange)
MAX_TOOL_OUTPUT_CHARS = 200     # Prune tool outputs longer than this

# Rough estimate: 1 token ≈ 4 chars
CHARS_PER_TOKEN = 4
# Claude Sonnet context window (conservative estimate for caching)
CONTEXT_WINDOW_TOKENS = 180_000
THRESHOLD_TOKENS = int(CONTEXT_WINDOW_TOKENS * COMPRESSION_THRESHOLD)


class ContextCompressor:
    def __init__(self):
        from memory.sessiondb import SessionDB
        self.db = SessionDB()

    def estimate_tokens(self, turns: list[dict]) -> int:
        """Rough token estimate from character count."""
        total_chars = sum(len(t.get("content", "")) for t in turns)
        return total_chars // CHARS_PER_TOKEN

    def needs_compression(self, session_id: str) -> bool:
        """Check if session is approaching context limit."""
        turns = self.db.get_turns(session_id)
        estimated = self.estimate_tokens(turns)
        return estimated >= THRESHOLD_TOKENS

    def prune_tool_outputs(self, turns: list[dict]) -> tuple[list[dict], int]:
        """
        Phase 1: Replace verbose tool outputs outside the protected tail.
        Returns (pruned_turns, chars_saved).
        No LLM call needed.
        """
        n = len(turns)
        tail_start = max(PROTECT_FIRST_N, n - PROTECT_LAST_N)
        chars_saved = 0
        pruned = []

        for i, turn in enumerate(turns):
            if (i >= PROTECT_FIRST_N and
                i < tail_start and
                turn.get("role") == "tool" and
                len(turn.get("content", "")) > MAX_TOOL_OUTPUT_CHARS):
                
                saved = len(turn["content"]) - 50
                chars_saved += saved
                pruned.append({
                    **turn,
                    "content": "[tool output pruned to save context space]"
                })
            else:
                pruned.append(turn)

        return pruned, chars_saved

    def summarize_middle(self, turns: list[dict]) -> str:
        """
        Phase 2: Summarize middle turns using claude --print.
        Uses Max subscription — no API cost.
        """
        n = len(turns)
        tail_start = max(PROTECT_FIRST_N, n - PROTECT_LAST_N)
        middle = turns[PROTECT_FIRST_N:tail_start]

        if not middle:
            return ""

        # Format turns for summarization
        formatted = []
        for t in middle:
            role = t.get("role", "unknown")
            agent = t.get("agent", "unknown")
            content = t.get("content", "")[:800]  # truncate for summary prompt
            formatted.append(f"[{agent}/{role}]: {content}")

        transcript = "\n".join(formatted)

        prompt = f"""Summarize this agent session transcript into a structured context block.
Be specific about files, commands, decisions, and current state.

TRANSCRIPT:
{transcript}

Output this exact structure:

## Goal
[What was being accomplished]

## Constraints & Preferences
[Important decisions, coding conventions, constraints established]

## Progress
### Done
[Completed work — specific files changed, commands run, results]
### In Progress
[Work currently underway, last state]
### Blocked
[Any blockers encountered]

## Key Decisions
[Important technical decisions and reasoning]

## Relevant Files
[Files read/modified/created with brief note]

## Next Steps
[What needs to happen next]

## Critical Context
[Specific values, error messages, config details that must be preserved]

Keep the summary under 500 words. Be specific, not vague."""

        try:
            result = subprocess.run(
                ["claude", "--print", "--permission-mode", "bypassPermissions", prompt],
                capture_output=True, text=True, cwd=str(FORGE_ROOT), timeout=60
            )
            return result.stdout.strip()
        except Exception as e:
            return f"[Summary failed: {e}]"

    def compress(self, session_id: str) -> dict:
        """
        Full compression: prune tools + summarize middle.
        Returns stats dict.
        """
        turns = self.db.get_turns(session_id)
        if not turns:
            return {"error": "session not found or empty"}

        n = len(turns)
        original_tokens = self.estimate_tokens(turns)
        print(f"  Session {session_id[:8]}... — {n} turns, ~{original_tokens:,} tokens")

        # Phase 1: Prune tool outputs
        pruned_turns, chars_saved = self.prune_tool_outputs(turns)
        print(f"  Phase 1: Pruned {chars_saved:,} chars from tool outputs")

        # Phase 2: Summarize middle if still over threshold
        after_prune_tokens = self.estimate_tokens(pruned_turns)
        summary = ""
        if after_prune_tokens >= THRESHOLD_TOKENS:
            print(f"  Phase 2: Generating summary of middle turns...")
            summary = self.summarize_middle(pruned_turns)
            print(f"  Summary: {len(summary)} chars")

        # Store summary in session_meta
        if summary:
            self.db.end_session(session_id, summary=summary)
            print(f"  ✅ Summary stored in session_meta")

        final_tokens = self.estimate_tokens(pruned_turns)
        print(f"  Result: ~{original_tokens:,} → ~{final_tokens:,} tokens ({round((1 - final_tokens/original_tokens)*100)}% reduction)")

        return {
            "session_id": session_id,
            "original_tokens": original_tokens,
            "final_tokens": final_tokens,
            "chars_saved_pruning": chars_saved,
            "summary_length": len(summary),
            "compressed_at": datetime.now(timezone.utc).isoformat()
        }

    def status(self, session_id: str) -> dict:
        """Show context usage for a session."""
        turns = self.db.get_turns(session_id)
        estimated = self.estimate_tokens(turns)
        pct = round(estimated / CONTEXT_WINDOW_TOKENS * 100)
        return {
            "session_id": session_id,
            "turns": len(turns),
            "estimated_tokens": estimated,
            "context_window": CONTEXT_WINDOW_TOKENS,
            "usage_pct": pct,
            "needs_compression": estimated >= THRESHOLD_TOKENS,
            "threshold_pct": int(COMPRESSION_THRESHOLD * 100)
        }


# ── Cache Optimization Guide ───────────────────────────────────────────────────

CACHE_OPTIMIZATION_NOTES = """
FORGE Cache Optimization Strategy
===================================

Claude Code (Claude Max subscription) handles prompt caching automatically.
These are the structural rules that maximize cache hit rate:

1. STABLE PREFIX FIRST
   - CLAUDE.md (system prompt) = always first, never changes mid-session
   - Memory block (context_builder.py output) = loaded once at session start
   - Agent soul (.claude/agents/atlas.md) = loaded once, never mutated
   Cache reuse: HIGH — these thousands of tokens are cached after turn 1

2. KEEP STABLE CONTENT STABLE
   - Never modify CLAUDE.md during a session
   - Memory files (MEMORY.md, USER.md, PROJECT.md) = updated only between sessions
   - If you must update memory mid-session, do it AFTER the session ends
   Cache reuse: Any change to the prefix invalidates the cache for all subsequent turns

3. SESSION LENGTH vs CACHE TRADE-OFF
   - Longer sessions = more cache hits (same prefix reused across many turns)
   - But: context window fills up, reducing effective cache
   - Compression (context_compressor.py) keeps sessions alive longer
   - Target: 50-60% context usage before compressing

4. CRON JOBS = ISOLATED SESSIONS
   - Each `claude --print` call is a fresh session
   - System prompt (CLAUDE.md + memory) is re-cached on first tool call
   - Hermes pattern: keep system prompt identical across cron runs for max cache reuse
   - Our daemon already does this — same CLAUDE.md for all agents

5. WHAT WE CANNOT CONTROL (on Max subscription)
   - Cache TTL: Anthropic sets it at ~5 minutes (exact value varies)
   - Cache size: Anthropic manages this transparently
   - Cache keys: Determined by Anthropic based on prompt prefix hash

6. WHAT WE CAN CONTROL
   - Prompt structure (stable parts first — we do this)
   - Session length (compression keeps sessions alive longer)
   - Context file size (bounded memory = smaller, more cacheable system prompt)
   - Cron job frequency (more frequent = more likely cache is warm)
"""


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] == "guide":
        print(CACHE_OPTIMIZATION_NOTES)
        sys.exit(0)

    cmd = args[0]
    rest = args[1:]

    compressor = ContextCompressor()

    if cmd == "compress":
        if not rest:
            print("Usage: compress <session_id>")
            sys.exit(1)
        stats = compressor.compress(rest[0])
        print(json.dumps(stats, indent=2))

    elif cmd == "status":
        if not rest:
            print("Usage: status <session_id>")
            sys.exit(1)
        s = compressor.status(rest[0])
        needs = "⚠️  YES — compress now" if s["needs_compression"] else "✅ No"
        print(f"\n📊 Session {s['session_id'][:8]}...")
        print(f"  Turns:            {s['turns']}")
        print(f"  Est. tokens:      {s['estimated_tokens']:,}")
        print(f"  Context usage:    {s['usage_pct']}% of {s['context_window']:,}")
        print(f"  Needs compress:   {needs} (threshold: {s['threshold_pct']}%)")

    elif cmd == "prune-tools":
        if not rest:
            print("Usage: prune-tools <session_id>")
            sys.exit(1)
        from memory.sessiondb import SessionDB
        db = SessionDB()
        turns = db.get_turns(rest[0])
        _, saved = compressor.prune_tool_outputs(turns)
        print(f"Would save {saved:,} chars from tool output pruning")

    elif cmd == "guide":
        print(CACHE_OPTIMIZATION_NOTES)

    else:
        print(f"Unknown command: {cmd}")
        print("Commands: compress <session_id>, status <session_id>, prune-tools <session_id>, guide")
        sys.exit(1)
