#!/bin/bash
# forge-daemon.sh — FORGE Runtime Daemon
#
# This is the heartbeat + cron engine that runs independently of OpenClaw.
# It replaces OpenClaw's cron scheduler for FORGE-specific jobs.
#
# Usage:
#   ./daemon/forge-daemon.sh start     # Start daemon in background
#   ./daemon/forge-daemon.sh stop      # Stop daemon
#   ./daemon/forge-daemon.sh status    # Check if running
#   ./daemon/forge-daemon.sh logs      # Tail daemon logs
#
# The daemon:
#   1. Reads cron jobs from daemon/crons/*.json
#   2. Fires them on schedule via `claude --print` (non-interactive)
#   3. Sends results to Slack channels
#   4. Runs heartbeat checks every N minutes
#   5. Writes logs to daemon/logs/

set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$FORGE_ROOT/daemon"
CRONS_DIR="$DAEMON_DIR/crons"
LOGS_DIR="$DAEMON_DIR/logs"
PID_FILE="$DAEMON_DIR/forge-daemon.pid"
LOG_FILE="$LOGS_DIR/daemon.log"

mkdir -p "$LOGS_DIR" "$CRONS_DIR"

# ── Logging ──────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "FORGE daemon already running (PID $(cat "$PID_FILE"))"
    exit 1
  fi

  log "Starting FORGE daemon..."
  nohup bash "$0" _run >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  log "FORGE daemon started (PID $!)"
  echo "FORGE daemon started (PID $!). Logs: $LOG_FILE"
}

cmd_stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "FORGE daemon not running"
    exit 0
  fi
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    rm -f "$PID_FILE"
    log "FORGE daemon stopped (PID $PID)"
    echo "FORGE daemon stopped"
  else
    rm -f "$PID_FILE"
    echo "FORGE daemon was not running (stale PID file removed)"
  fi
}

cmd_status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "✅ FORGE daemon running (PID $(cat "$PID_FILE"))"
    echo "Log: $LOG_FILE"
    echo ""
    echo "Registered cron jobs:"
    for f in "$CRONS_DIR"/*.json 2>/dev/null; do
      [ -f "$f" ] && jq -r '"  • \(.name) — \(.schedule)"' "$f"
    done
  else
    echo "❌ FORGE daemon not running"
  fi
}

cmd_logs() {
  tail -f "$LOG_FILE"
}

# ── Main Run Loop ─────────────────────────────────────────────────────────────

cmd_run() {
  log "FORGE daemon run loop started"
  
  # Track last run times per job (key=job_name, value=epoch seconds)
  declare -A LAST_RUN

  while true; do
    NOW=$(date +%s)
    HOUR=$(date +%H)
    MINUTE=$(date +%M)
    DOW=$(date +%u)   # 1=Mon ... 7=Sun

    # ── Process each cron job ──────────────────────────────────────────────

    for CRON_FILE in "$CRONS_DIR"/*.json; do
      [ -f "$CRON_FILE" ] || continue

      JOB_NAME=$(jq -r '.name' "$CRON_FILE")
      SCHEDULE=$(jq -r '.schedule' "$CRON_FILE")
      ENABLED=$(jq -r '.enabled // true' "$CRON_FILE")
      QUIET_START=$(jq -r '.quiet_start // "23"' "$CRON_FILE")
      QUIET_END=$(jq -r '.quiet_end // "7"' "$CRON_FILE")

      [ "$ENABLED" = "false" ] && continue

      # Quiet hours check (don't fire during sleep time unless forced)
      FORCED=$(jq -r '.ignore_quiet // false' "$CRON_FILE")
      if [ "$FORCED" != "true" ]; then
        HOUR_INT=$((10#$HOUR))
        QUIET_S=$((10#$QUIET_START))
        QUIET_E=$((10#$QUIET_END))
        if [ $HOUR_INT -ge $QUIET_S ] || [ $HOUR_INT -lt $QUIET_E ]; then
          continue
        fi
      fi

      # Check if due (simple interval-based for now; cron expr support via daemon/lib/cron-check.sh)
      INTERVAL=$(jq -r '.interval_minutes // 0' "$CRON_FILE")
      LAST="${LAST_RUN[$JOB_NAME]:-0}"
      
      if [ "$INTERVAL" -gt 0 ]; then
        ELAPSED=$(( (NOW - LAST) / 60 ))
        [ "$ELAPSED" -lt "$INTERVAL" ] && continue
      fi

      # Cron expression check (delegates to helper)
      CRON_EXPR=$(jq -r '.cron // ""' "$CRON_FILE")
      if [ -n "$CRON_EXPR" ]; then
        if ! bash "$DAEMON_DIR/lib/cron-check.sh" "$CRON_EXPR" "$HOUR" "$MINUTE" "$DOW"; then
          continue
        fi
      fi

      # ── Fire the job ──────────────────────────────────────────────────────
      LAST_RUN[$JOB_NAME]=$NOW
      log "Firing job: $JOB_NAME"

      PROMPT=$(jq -r '.prompt' "$CRON_FILE")
      AGENT=$(jq -r '.agent // "ray"' "$CRON_FILE")
      SLACK_CHANNEL=$(jq -r '.slack_channel // ""' "$CRON_FILE")
      JOB_LOG="$LOGS_DIR/${JOB_NAME}-$(date +%Y%m%d-%H%M).log"

      # Fire via claude --print (non-interactive, isolated)
      (
        cd "$FORGE_ROOT"
        OUTPUT=$(claude --print \
          --agent "$AGENT" \
          --permission-mode bypassPermissions \
          "$PROMPT" 2>&1) || true

        echo "$OUTPUT" > "$JOB_LOG"
        log "Job $JOB_NAME completed. Log: $JOB_LOG"

        # Post to Slack if configured
        if [ -n "$SLACK_CHANNEL" ] && [ -n "${SLACK_BOT_TOKEN:-}" ]; then
          SNIPPET=$(echo "$OUTPUT" | head -20)
          curl -s -X POST "https://slack.com/api/chat.postMessage" \
            -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"channel\": \"$SLACK_CHANNEL\", \"text\": \"🔥 *$JOB_NAME* completed\n\`\`\`$SNIPPET\`\`\`\"}" \
            > /dev/null
        fi
      ) &

    done

    # ── Heartbeat ─────────────────────────────────────────────────────────
    HEARTBEAT_FILE="$DAEMON_DIR/heartbeat.json"
    if [ -f "$HEARTBEAT_FILE" ]; then
      HB_INTERVAL=$(jq -r '.interval_minutes // 120' "$HEARTBEAT_FILE")
      HB_LAST="${LAST_RUN[__heartbeat__]:-0}"
      HB_ELAPSED=$(( (NOW - HB_LAST) / 60 ))

      if [ "$HB_ELAPSED" -ge "$HB_INTERVAL" ]; then
        LAST_RUN[__heartbeat__]=$NOW
        HB_PROMPT=$(jq -r '.prompt' "$HEARTBEAT_FILE")
        HB_AGENT=$(jq -r '.agent // "ray"' "$HEARTBEAT_FILE")
        HB_CHANNEL=$(jq -r '.slack_channel // "#forge-pipeline"' "$HEARTBEAT_FILE")
        log "Firing heartbeat check"

        (
          cd "$FORGE_ROOT"
          RESULT=$(claude --print \
            --agent "$HB_AGENT" \
            --permission-mode bypassPermissions \
            "$HB_PROMPT" 2>&1) || true

          # Only post to Slack if heartbeat found something worth reporting
          if echo "$RESULT" | grep -qiv "HEARTBEAT_OK"; then
            if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
              curl -s -X POST "https://slack.com/api/chat.postMessage" \
                -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"channel\": \"$HB_CHANNEL\", \"text\": \"💓 *Heartbeat alert*\n$RESULT\"}" \
                > /dev/null
            fi
          fi
        ) &
      fi
    fi

    # Sleep 60 seconds between checks
    sleep 60
  done
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

case "${1:-help}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  restart) cmd_stop; sleep 1; cmd_start ;;
  _run)    cmd_run ;;  # internal — called by nohup
  *)
    echo "Usage: $0 {start|stop|status|logs|restart}"
    echo ""
    echo "FORGE Runtime Daemon — cron scheduler + heartbeat engine"
    echo "Runs independently of OpenClaw."
    ;;
esac
