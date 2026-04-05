#!/bin/bash
# forge-cron.sh — Manage FORGE cron jobs
#
# Usage:
#   ./daemon/forge-cron.sh list              # List all jobs with status
#   ./daemon/forge-cron.sh run <job-name>    # Run a job immediately
#   ./daemon/forge-cron.sh enable <name>     # Enable a job
#   ./daemon/forge-cron.sh disable <name>    # Disable a job
#   ./daemon/forge-cron.sh add               # Interactive job creator
#   ./daemon/forge-cron.sh logs [name]       # Show job logs

set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$FORGE_ROOT/daemon"
CRONS_DIR="$DAEMON_DIR/crons"
LOGS_DIR="$DAEMON_DIR/logs"

cmd_list() {
  echo "🔥 FORGE Cron Jobs"
  echo "─────────────────────────────────────────────────────"
  printf "%-30s %-20s %-10s\n" "NAME" "SCHEDULE" "STATUS"
  echo "─────────────────────────────────────────────────────"

  for f in "$CRONS_DIR"/*.json; do
    [ -f "$f" ] || continue
    NAME=$(jq -r '.name' "$f")
    SCHEDULE=$(jq -r '.cron // "every \(.interval_minutes)min"' "$f")
    ENABLED=$(jq -r '.enabled // true' "$f")
    STATUS="✅ enabled"
    [ "$ENABLED" = "false" ] && STATUS="⏸  disabled"
    printf "%-30s %-20s %-10s\n" "$NAME" "$SCHEDULE" "$STATUS"
  done

  echo ""
  echo "Heartbeat: $(jq -r '"every \(.interval_minutes) min"' "$DAEMON_DIR/heartbeat.json" 2>/dev/null || echo "not configured")"
}

cmd_run() {
  local NAME="${1:-}"
  [ -z "$NAME" ] && { echo "Usage: $0 run <job-name>"; exit 1; }

  local CRON_FILE="$CRONS_DIR/${NAME}.json"
  [ -f "$CRON_FILE" ] || { echo "Job not found: $NAME"; exit 1; }

  local PROMPT AGENT SLACK_CHANNEL
  PROMPT=$(jq -r '.prompt' "$CRON_FILE")
  AGENT=$(jq -r '.agent // "atlas"' "$CRON_FILE")
  SLACK_CHANNEL=$(jq -r '.slack_channel // ""' "$CRON_FILE")

  echo "Running job: $NAME (agent: $AGENT)"
  local JOB_LOG="$LOGS_DIR/${NAME}-$(date +%Y%m%d-%H%M).log"

  cd "$FORGE_ROOT"
  OUTPUT=$(claude --print \
    --agent "$AGENT" \
    --permission-mode bypassPermissions \
    "$PROMPT" 2>&1) || true

  echo "$OUTPUT" | tee "$JOB_LOG"

  if [ -n "$SLACK_CHANNEL" ] && [ -n "${SLACK_BOT_TOKEN:-}" ]; then
    SNIPPET=$(echo "$OUTPUT" | head -20)
    curl -s -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"channel\": \"$SLACK_CHANNEL\", \"text\": \"🔥 *$NAME* (manual run)\n\`\`\`$SNIPPET\`\`\`\"}" \
      > /dev/null && echo "[Slack: posted to $SLACK_CHANNEL]"
  fi

  echo "Log saved: $JOB_LOG"
}

cmd_enable() {
  local NAME="${1:-}"
  [ -z "$NAME" ] && { echo "Usage: $0 enable <job-name>"; exit 1; }
  local CRON_FILE="$CRONS_DIR/${NAME}.json"
  [ -f "$CRON_FILE" ] || { echo "Job not found: $NAME"; exit 1; }
  jq '.enabled = true' "$CRON_FILE" > "${CRON_FILE}.tmp" && mv "${CRON_FILE}.tmp" "$CRON_FILE"
  echo "✅ Enabled: $NAME"
}

cmd_disable() {
  local NAME="${1:-}"
  [ -z "$NAME" ] && { echo "Usage: $0 disable <job-name>"; exit 1; }
  local CRON_FILE="$CRONS_DIR/${NAME}.json"
  [ -f "$CRON_FILE" ] || { echo "Job not found: $NAME"; exit 1; }
  jq '.enabled = false' "$CRON_FILE" > "${CRON_FILE}.tmp" && mv "${CRON_FILE}.tmp" "$CRON_FILE"
  echo "⏸  Disabled: $NAME"
}

cmd_logs() {
  local NAME="${1:-}"
  if [ -z "$NAME" ]; then
    tail -50 "$DAEMON_DIR/logs/daemon.log" 2>/dev/null || echo "No daemon log found"
  else
    local LATEST
    LATEST=$(ls -t "$LOGS_DIR/${NAME}-"*.log 2>/dev/null | head -1)
    [ -z "$LATEST" ] && { echo "No logs found for: $NAME"; exit 1; }
    cat "$LATEST"
  fi
}

case "${1:-list}" in
  list)         cmd_list ;;
  run)          cmd_run "${2:-}" ;;
  enable)       cmd_enable "${2:-}" ;;
  disable)      cmd_disable "${2:-}" ;;
  logs)         cmd_logs "${2:-}" ;;
  *)
    echo "Usage: $0 {list|run <name>|enable <name>|disable <name>|logs [name]}"
    ;;
esac
