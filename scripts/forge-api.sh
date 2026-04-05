#!/bin/bash
# forge-api.sh — CLI wrapper for the FORGE Dashboard API
#
# Agents use this to read/write tasks, log activity, and update their status
# without needing to know the API URL or auth details.
#
# Usage:
#   ./scripts/forge-api.sh tasks list
#   ./scripts/forge-api.sh tasks list --status backlog
#   ./scripts/forge-api.sh tasks get <id>
#   ./scripts/forge-api.sh tasks create --title "..." --assignee jeff --priority high
#   ./scripts/forge-api.sh tasks update <id> --status in-progress
#   ./scripts/forge-api.sh tasks update <id> --assignee tamara --status review
#   ./scripts/forge-api.sh tasks done <id>
#
#   ./scripts/forge-api.sh agents list
#   ./scripts/forge-api.sh agents status <id> --status working --task <task-id>
#   ./scripts/forge-api.sh agents idle <id>
#
#   ./scripts/forge-api.sh activity log --agent jeff --task <id> --message "started implementation"
#   ./scripts/forge-api.sh activity recent
#
#   ./scripts/forge-api.sh projects list
#   ./scripts/forge-api.sh projects active
#
#   ./scripts/forge-api.sh pipeline log <task-id> --step spec-approved --agent ray
#   ./scripts/forge-api.sh pipeline validate <task-id>

set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$FORGE_ROOT/.env" ] && set -a && source "$FORGE_ROOT/.env" && set +a

API="${FORGE_API_URL:-http://localhost:3400}"

# ── Helpers ───────────────────────────────────────────────────────────────────

api_get()  { curl -sf "$API$1" 2>/dev/null; }
api_post() { curl -sf -X POST -H "Content-Type: application/json" -d "$2" "$API$1" 2>/dev/null; }
api_patch(){ curl -sf -X PATCH -H "Content-Type: application/json" -d "$2" "$API$1" 2>/dev/null; }

pretty() { python3 -m json.tool 2>/dev/null || cat; }

# ── Tasks ─────────────────────────────────────────────────────────────────────

cmd_tasks() {
  local sub="${1:-list}"; shift || true

  case "$sub" in
    list)
      local STATUS="" ASSIGNEE=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --status)   STATUS="$2";   shift 2 ;;
          --assignee) ASSIGNEE="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      local QS=""
      [ -n "$STATUS" ]   && QS="${QS:+$QS&}status=$STATUS"
      [ -n "$ASSIGNEE" ] && QS="${QS:+$QS&}assignee=$ASSIGNEE"
      api_get "/api/tasks${QS:+?$QS}" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
if not tasks:
    print('No tasks found.')
else:
    for t in tasks:
        assignee = t.get('assignee') or 'unassigned'
        print(f\"[{t['status']:12}] [{t['priority']:6}] {t['id'][:8]}  {t['title'][:60]}  ({assignee})\")
"
      ;;

    get)
      local ID="${1:-}"; [ -z "$ID" ] && { echo "Usage: tasks get <id>"; exit 1; }
      api_get "/api/tasks/$ID" | pretty
      ;;

    create)
      local TITLE="" ASSIGNEE="" PRIORITY="medium" DESCRIPTION="" PROJECT_ID=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --title)       TITLE="$2";       shift 2 ;;
          --assignee)    ASSIGNEE="$2";    shift 2 ;;
          --priority)    PRIORITY="$2";    shift 2 ;;
          --description) DESCRIPTION="$2"; shift 2 ;;
          --project)     PROJECT_ID="$2";  shift 2 ;;
          *) shift ;;
        esac
      done
      [ -z "$TITLE" ] && { echo "Usage: tasks create --title '...' [--assignee jeff] [--priority high]"; exit 1; }
      PAYLOAD=$(python3 -c "
import json
d = {'title': '$TITLE', 'priority': '$PRIORITY', 'status': 'backlog'}
if '$ASSIGNEE': d['assignee'] = '$ASSIGNEE'
if '$DESCRIPTION': d['description'] = '$DESCRIPTION'
if '$PROJECT_ID': d['project_id'] = '$PROJECT_ID'
print(json.dumps(d))
")
      api_post "/api/tasks" "$PAYLOAD" | python3 -c "
import sys, json
t = json.load(sys.stdin)
print(f\"Created: {t['id']} — {t['title']}\")
"
      ;;

    update)
      local ID="${1:-}"; shift || true
      [ -z "$ID" ] && { echo "Usage: tasks update <id> [--status ...] [--assignee ...]"; exit 1; }
      local UPDATES="{}"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --status)   UPDATES=$(echo "$UPDATES" | python3 -c "import sys,json; d=json.load(sys.stdin); d['status']='$2'; print(json.dumps(d))"); shift 2 ;;
          --assignee) UPDATES=$(echo "$UPDATES" | python3 -c "import sys,json; d=json.load(sys.stdin); d['assignee']='$2'; print(json.dumps(d))"); shift 2 ;;
          --pr-url)   UPDATES=$(echo "$UPDATES" | python3 -c "import sys,json; d=json.load(sys.stdin); d['pr_url']='$2'; print(json.dumps(d))"); shift 2 ;;
          --pr-number)UPDATES=$(echo "$UPDATES" | python3 -c "import sys,json; d=json.load(sys.stdin); d['pr_number']=int('$2'); print(json.dumps(d))"); shift 2 ;;
          *) shift ;;
        esac
      done
      api_patch "/api/tasks/$ID" "$UPDATES" | python3 -c "
import sys, json
t = json.load(sys.stdin)
print(f\"Updated: {t['id'][:8]} — {t['title']} → {t['status']}\")
"
      ;;

    done)
      local ID="${1:-}"; [ -z "$ID" ] && { echo "Usage: tasks done <id>"; exit 1; }
      api_patch "/api/tasks/$ID" '{"status":"done"}' | python3 -c "
import sys, json
t = json.load(sys.stdin)
print(f\"Done: {t['id'][:8]} — {t['title']}\")
"
      ;;

    *)
      echo "Unknown tasks subcommand: $sub"
      exit 1
      ;;
  esac
}

# ── Agents ────────────────────────────────────────────────────────────────────

cmd_agents() {
  local sub="${1:-list}"; shift || true

  case "$sub" in
    list)
      api_get "/api/agents" | python3 -c "
import sys, json
agents = json.load(sys.stdin)
for a in agents:
    task = a.get('current_task_id') or '-'
    print(f\"{a.get('emoji','?')} {a['id']:10} [{a['status']:8}]  task: {task[:20]}\")
"
      ;;

    status)
      local ID="${1:-}"; shift || true
      [ -z "$ID" ] && { echo "Usage: agents status <id> --status working --task <task-id>"; exit 1; }
      local STATUS="" TASK_ID=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --status) STATUS="$2"; shift 2 ;;
          --task)   TASK_ID="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      PAYLOAD=$(python3 -c "
import json
d = {}
if '$STATUS': d['status'] = '$STATUS'
if '$TASK_ID': d['current_task_id'] = '$TASK_ID'
print(json.dumps(d))
")
      api_patch "/api/agents/$ID" "$PAYLOAD" | python3 -c "
import sys, json
a = json.load(sys.stdin)
print(f\"Agent {a['id']} → status: {a['status']}\")
"
      ;;

    idle)
      local ID="${1:-}"; [ -z "$ID" ] && { echo "Usage: agents idle <id>"; exit 1; }
      api_patch "/api/agents/$ID" '{"status":"idle","current_task_id":null}' | python3 -c "
import sys, json
a = json.load(sys.stdin)
print(f\"Agent {a['id']} → idle\")
"
      ;;

    *)
      echo "Unknown agents subcommand: $sub"
      exit 1
      ;;
  esac
}

# ── Activity ──────────────────────────────────────────────────────────────────

cmd_activity() {
  local sub="${1:-recent}"; shift || true

  case "$sub" in
    log)
      local AGENT="" TASK_ID="" MSG="" TYPE="agent_action"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --agent)   AGENT="$2";   shift 2 ;;
          --task)    TASK_ID="$2"; shift 2 ;;
          --message) MSG="$2";     shift 2 ;;
          --type)    TYPE="$2";    shift 2 ;;
          *) shift ;;
        esac
      done
      PAYLOAD=$(python3 -c "
import json
d = {'type': '$TYPE'}
if '$AGENT':   d['agent_id'] = '$AGENT'
if '$TASK_ID': d['task_id']  = '$TASK_ID'
if '$MSG':     d['message']  = '$MSG'
print(json.dumps(d))
")
      api_post "/api/activity" "$PAYLOAD" | python3 -c "
import sys, json
a = json.load(sys.stdin)
print(f\"Logged: #{a['id']} — {a['type']}\")
"
      ;;

    recent)
      api_get "/api/activity?limit=20" | python3 -c "
import sys, json
items = json.load(sys.stdin)
for a in items:
    agent = a.get('agent_id') or 'system'
    msg = (a.get('message') or '')[:70]
    ts = a['created_at'][:16]
    print(f\"{ts}  [{agent:8}]  {msg}\")
"
      ;;

    *)
      echo "Unknown activity subcommand: $sub"
      exit 1
      ;;
  esac
}

# ── Projects ──────────────────────────────────────────────────────────────────

cmd_projects() {
  local sub="${1:-list}"; shift || true

  case "$sub" in
    list)
      api_get "/api/projects" | python3 -c "
import sys, json
projects = json.load(sys.stdin)
for p in projects:
    print(f\"[{p['status']:8}] {p['id'][:8]}  {p['name']}\")
"
      ;;

    active)
      # Returns the first active project (set as active in config or first active status)
      api_get "/api/projects" | python3 -c "
import sys, json
projects = json.load(sys.stdin)
active = [p for p in projects if p.get('status') == 'active']
if active:
    p = active[0]
    print(f\"Active project: {p['name']}\")
    print(f\"ID: {p['id']}\")
    print(f\"Repo: {p.get('repo_url') or 'not set'}\")
else:
    print('No active project found')
"
      ;;

    *)
      echo "Unknown projects subcommand: $sub"
      exit 1
      ;;
  esac
}

# ── Pipeline ──────────────────────────────────────────────────────────────────

cmd_pipeline() {
  local sub="${1:-}"; shift || true

  case "$sub" in
    log)
      local TASK_ID="${1:-}"; shift || true
      [ -z "$TASK_ID" ] && { echo "Usage: pipeline log <task-id> --step spec-approved --agent ray"; exit 1; }
      local STEP="" AGENT=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --step)  STEP="$2";  shift 2 ;;
          --agent) AGENT="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      PAYLOAD=$(python3 -c "
import json
d = {'step': '$STEP'}
if '$AGENT': d['agent_id'] = '$AGENT'
print(json.dumps(d))
")
      api_post "/api/tasks/$TASK_ID/pipeline" "$PAYLOAD" | python3 -c "
import sys, json
p = json.load(sys.stdin)
print(f\"Pipeline step logged: {p['step']} (task: {p['task_id'][:8]})\")
"
      ;;

    validate)
      local TASK_ID="${1:-}"; [ -z "$TASK_ID" ] && { echo "Usage: pipeline validate <task-id>"; exit 1; }
      api_get "/api/tasks/$TASK_ID/pipeline/validate" | python3 -c "
import sys, json
v = json.load(sys.stdin)
print('Valid:', v['valid'])
print('Completed:', ', '.join(v['completed']))
if v['missing']:
    print('Missing:', ', '.join(v['missing']))
"
      ;;

    *)
      echo "Usage: pipeline {log <task-id> --step ... --agent ... | validate <task-id>}"
      exit 1
      ;;
  esac
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

case "${1:-help}" in
  tasks)    shift; cmd_tasks "$@" ;;
  agents)   shift; cmd_agents "$@" ;;
  activity) shift; cmd_activity "$@" ;;
  projects) shift; cmd_projects "$@" ;;
  pipeline) shift; cmd_pipeline "$@" ;;
  health)
    api_get "/api/health" | python3 -c "import sys,json; d=json.load(sys.stdin); print('✅ Dashboard API:', d['status'], d['timestamp'])"
    ;;
  *)
    echo "Usage: forge-api.sh {tasks|agents|activity|projects|pipeline|health}"
    echo ""
    echo "Examples:"
    echo "  ./scripts/forge-api.sh tasks list --status backlog"
    echo "  ./scripts/forge-api.sh tasks update <id> --status in-progress --assignee jeff"
    echo "  ./scripts/forge-api.sh agents status jeff --status working --task <id>"
    echo "  ./scripts/forge-api.sh activity log --agent jeff --task <id> --message 'started'"
    echo "  ./scripts/forge-api.sh pipeline log <id> --step spec-approved --agent ray"
    ;;
esac
