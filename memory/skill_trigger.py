#!/usr/bin/env python3.13
"""
skill_trigger.py — FORGE Skill Auto-Creation

Runs after sessions with 5+ tool calls. Evaluates whether something
worth saving was learned, and creates or patches skills accordingly.

All evaluation runs via `claude --print` — uses Max subscription, not API.

Usage:
    python memory/skill_trigger.py evaluate <session_id>
    python memory/skill_trigger.py list-pending
    python memory/skill_trigger.py run-pending      # evaluate all pending sessions
"""

import sys
import json
import subprocess
import os
from pathlib import Path
from datetime import datetime, timezone

FORGE_ROOT = Path(__file__).parent.parent
SKILLS_DIR = FORGE_ROOT / ".claude" / "skills"
PENDING_FILE = FORGE_ROOT / "memory" / ".pending_evaluations.json"

# Minimum tool calls to trigger evaluation
MIN_TOOL_CALLS = 5


class SkillTrigger:
    def __init__(self):
        SKILLS_DIR.mkdir(parents=True, exist_ok=True)
        PENDING_FILE.parent.mkdir(parents=True, exist_ok=True)

    def _load_pending(self) -> list:
        if not PENDING_FILE.exists():
            return []
        return json.loads(PENDING_FILE.read_text())

    def _save_pending(self, pending: list):
        PENDING_FILE.write_text(json.dumps(pending, indent=2))

    def mark_pending(self, session_id: str, agent: str, turn_count: int, task_id: str = None):
        """Mark a session for skill evaluation after it ends."""
        pending = self._load_pending()
        pending.append({
            "session_id": session_id,
            "agent": agent,
            "turn_count": turn_count,
            "task_id": task_id,
            "queued_at": datetime.now(timezone.utc).isoformat()
        })
        self._save_pending(pending)

    def list_pending(self) -> list:
        return self._load_pending()

    def _get_session_content(self, session_id: str) -> str:
        """Load session turns from SessionDB for evaluation."""
        try:
            sys.path.insert(0, str(FORGE_ROOT))
            from memory.sessiondb import SessionDB
            db = SessionDB()
            turns = db.get_turns(session_id)
            if not turns:
                return None
            lines = []
            for t in turns:
                lines.append(f"[{t['agent']}/{t['role']}]: {t['content'][:500]}")
            return "\n".join(lines)
        except Exception as e:
            print(f"  Warning: could not load session: {e}")
            return None

    def _existing_skills(self) -> list[str]:
        """List existing skill names."""
        skills = []
        for f in SKILLS_DIR.rglob("*.md"):
            skills.append(str(f.relative_to(SKILLS_DIR)))
        return skills

    def evaluate(self, session_id: str, agent: str = "unknown") -> dict:
        """
        Evaluate a session for skill creation/patching.
        Returns: {should_create, should_patch, skill_name, content, patch_target, reason}
        """
        print(f"  Evaluating session {session_id[:8]}... (agent: {agent})")

        session_content = self._get_session_content(session_id)
        if not session_content:
            print(f"  No content found for session {session_id[:8]}. Skipping.")
            return {"should_create": False, "should_patch": False, "reason": "no content"}

        existing = self._existing_skills()
        existing_str = "\n".join(f"- {s}" for s in existing) if existing else "(none yet)"

        prompt = f"""You are reviewing a FORGE agent session to decide if anything worth saving as a reusable skill was learned.

SESSION TRANSCRIPT:
{session_content[:3000]}

EXISTING SKILLS:
{existing_str}

Evaluate:
1. Did the agent learn something non-obvious that would help future sessions?
2. Is there a reusable approach, pattern, or workflow worth documenting?
3. Did the agent encounter and resolve a non-trivial error in a reusable way?
4. Would future sessions benefit from this knowledge being pre-loaded?

If YES to any: either create a new skill or patch an existing one.

Respond with ONLY valid JSON (no markdown, no explanation outside the JSON):
{{
  "should_create": true|false,
  "should_patch": true|false,
  "reason": "one sentence explaining your decision",
  "skill_name": "category/skill-name (e.g. development/prisma-migrations)",
  "skill_content": "full SKILL.md content if creating, null if not",
  "patch_target": "path of existing skill to patch if patching, null if not",
  "patch_content": "new content for the patched skill if patching, null if not"
}}

Only create a skill if there is genuinely reusable, non-obvious knowledge. Do NOT create skills for trivial tasks."""

        try:
            result = subprocess.run(
                ["claude", "--print", "--permission-mode", "bypassPermissions", prompt],
                capture_output=True, text=True, cwd=str(FORGE_ROOT), timeout=120
            )
            output = result.stdout.strip()

            # Extract JSON from output
            import re
            json_match = re.search(r'\{.*\}', output, re.DOTALL)
            if not json_match:
                print(f"  Could not parse evaluation response")
                return {"should_create": False, "should_patch": False, "reason": "parse error"}

            evaluation = json.loads(json_match.group())

            if evaluation.get("should_create") and evaluation.get("skill_content"):
                self._create_skill(evaluation["skill_name"], evaluation["skill_content"])
                print(f"  ✅ Created skill: {evaluation['skill_name']}")

            elif evaluation.get("should_patch") and evaluation.get("patch_content"):
                self._patch_skill(evaluation["patch_target"], evaluation["patch_content"])
                print(f"  ✅ Patched skill: {evaluation['patch_target']}")

            else:
                print(f"  No skill needed: {evaluation.get('reason', 'no reason given')}")

            return evaluation

        except subprocess.TimeoutExpired:
            print(f"  Evaluation timed out")
            return {"should_create": False, "should_patch": False, "reason": "timeout"}
        except json.JSONDecodeError as e:
            print(f"  JSON parse error: {e}")
            return {"should_create": False, "should_patch": False, "reason": "json error"}
        except Exception as e:
            print(f"  Evaluation error: {e}")
            return {"should_create": False, "should_patch": False, "reason": str(e)}

    def _create_skill(self, skill_name: str, content: str):
        """Write a new skill file."""
        skill_path = SKILLS_DIR / (skill_name if skill_name.endswith(".md") else skill_name + ".md")
        skill_path.parent.mkdir(parents=True, exist_ok=True)
        # Add creation metadata
        header = f"<!-- auto-generated by skill_trigger.py on {datetime.now().strftime('%Y-%m-%d')} -->\n"
        skill_path.write_text(header + content)

    def _patch_skill(self, skill_path_str: str, new_content: str):
        """Overwrite an existing skill with improved content."""
        skill_path = SKILLS_DIR / skill_path_str
        if not skill_path.exists():
            print(f"  Warning: skill not found for patching: {skill_path_str}")
            self._create_skill(skill_path_str, new_content)
            return
        # Preserve original + add patch marker
        original = skill_path.read_text()
        patched = f"<!-- patched by skill_trigger.py on {datetime.now().strftime('%Y-%m-%d')} -->\n{new_content}"
        skill_path.write_text(patched)

    def run_pending(self):
        """Evaluate all pending sessions."""
        pending = self._load_pending()
        if not pending:
            print("No pending evaluations.")
            return

        print(f"Running {len(pending)} pending skill evaluations...\n")
        completed = []

        for item in pending:
            session_id = item["session_id"]
            agent = item.get("agent", "unknown")
            turn_count = item.get("turn_count", 0)

            if turn_count < MIN_TOOL_CALLS:
                print(f"  Skipping {session_id[:8]} (only {turn_count} turns, min {MIN_TOOL_CALLS})")
                completed.append(session_id)
                continue

            self.evaluate(session_id, agent)
            completed.append(session_id)
            print()

        # Remove completed from pending
        remaining = [p for p in pending if p["session_id"] not in completed]
        self._save_pending(remaining)
        print(f"Done. {len(completed)} evaluated, {len(remaining)} still pending.")


# ── CLI ────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)

    trigger = SkillTrigger()
    cmd = args[0]
    rest = args[1:]

    if cmd == "evaluate":
        if not rest:
            print("Usage: evaluate <session_id>")
            sys.exit(1)
        trigger.evaluate(rest[0], agent=rest[1] if len(rest) > 1 else "unknown")

    elif cmd == "list-pending":
        pending = trigger.list_pending()
        if not pending:
            print("No pending evaluations.")
        else:
            print(f"{len(pending)} pending:")
            for p in pending:
                print(f"  {p['session_id'][:8]}... agent:{p['agent']} turns:{p['turn_count']}")

    elif cmd == "run-pending":
        trigger.run_pending()

    else:
        print(f"Unknown command: {cmd}")
        print("Commands: evaluate, list-pending, run-pending")
        sys.exit(1)
