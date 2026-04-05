#!/bin/bash
# TaskCompleted hook — runs when a task is being marked complete
# Exit 0: allow completion
# Exit 2: block completion + send feedback
#
# Environment variables:
#   TASK_TITLE    — title of the task being completed
#   TASK_AGENT    — agent completing the task

TASK="${TASK_TITLE:-}"
AGENT="${TASK_AGENT:-}"

# Dev tasks require an open or merged PR
if echo "$TASK" | grep -qiE "^(Build|Fix|Implement):"; then
  PR_OPEN=$(gh pr list --state open --json number --jq 'length' 2>/dev/null || echo "0")
  PR_MERGED=$(gh pr list --state merged --json number --jq 'length' 2>/dev/null || echo "0")
  if [ "$PR_OPEN" -eq 0 ] && [ "$PR_MERGED" -eq 0 ]; then
    echo "Cannot complete a development task without a PR. Create or merge a PR first."
    exit 2
  fi
fi

# Research tasks require written output
if echo "$TASK" | grep -qiE "^Research:"; then
  # Check that a file was written or a task was created
  RECENT_MD=$(find .claude/skills .claude/memory content -name "*.md" -newer /tmp/.forge-last-research 2>/dev/null | head -1)
  if [ -z "$RECENT_MD" ]; then
    echo "Research task must produce written output (skill, memory entry, or content draft) before completing."
    exit 2
  fi
  # Update the timestamp marker
  touch /tmp/.forge-last-research
fi

exit 0
