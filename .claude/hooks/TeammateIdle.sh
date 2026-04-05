#!/bin/bash
# TeammateIdle hook — runs when a teammate is about to go idle
# Exit 0: allow idle
# Exit 2: reject + send feedback to keep the teammate working
#
# Environment variables available:
#   TEAMMATE_NAME — name of the agent going idle
#   TASK_ID       — current task ID (if any)
#   TASK_TITLE    — current task title (if any)

TEAMMATE="${TEAMMATE_NAME:-unknown}"
TASK="${TASK_TITLE:-}"

case "$TEAMMATE" in
  jeff)
    # Jeff must have an open PR before going idle on a dev task
    if echo "$TASK" | grep -qiE "^(Build|Fix|Implement):"; then
      PR_COUNT=$(gh pr list --author "@me" --state open --json number --jq 'length' 2>/dev/null || echo "0")
      if [ "$PR_COUNT" -eq 0 ]; then
        echo "Jeff: You have a dev task in progress but no open PR. Create a PR before going idle."
        exit 2
      fi
    fi
    ;;

  tamara)
    # Tamara must have left at least one review comment before going idle
    # (Implementation: check if review was submitted for current PR task)
    if echo "$TASK" | grep -qiE "^Review:"; then
      echo "Tamara: Make sure your review is submitted with specific feedback before going idle."
      # Soft reminder only — don't block (exit 2 would loop indefinitely)
    fi
    ;;

  saul)
    # Saul must have created at least one task from a research session
    if echo "$TASK" | grep -qiE "^Research:"; then
      # Check for tasks created in the last session (heuristic: look for task creation in output)
      : # TODO: implement task count check once task API is available
    fi
    ;;
esac

exit 0
