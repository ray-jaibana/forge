#!/bin/bash
# TaskCreated hook — runs when a task is being created
# Exit 0: allow creation
# Exit 2: reject + send feedback
#
# Environment variables:
#   TASK_TITLE    — proposed task title
#   TASK_AGENT    — agent creating the task

TASK="${TASK_TITLE:-}"

# All tasks must have a type prefix
if ! echo "$TASK" | grep -qE "^(Build|Research|Review|Content|Media|Fix|Deploy|Retrospective):"; then
  echo "Task title must start with a type prefix followed by a colon.
Valid prefixes: Build:, Research:, Review:, Content:, Media:, Fix:, Deploy:, Retrospective:
Example: 'Build: Add budget alert notifications'
Your title: '$TASK'"
  exit 2
fi

# Titles shouldn't be too vague
WORDS=$(echo "$TASK" | wc -w)
if [ "$WORDS" -lt 4 ]; then
  echo "Task title is too vague ($WORDS words). Be specific about what needs to be done.
Example: 'Build: Add email notifications for budget overruns' (not just 'Build: Notifications')"
  exit 2
fi

exit 0
