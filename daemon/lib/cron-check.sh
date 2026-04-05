#!/bin/bash
# cron-check.sh — Check if a cron expression matches the current time
#
# Usage: ./cron-check.sh "30 7 * * *" HOUR MINUTE DOW
#   HOUR    — current hour (00-23)
#   MINUTE  — current minute (00-59)
#   DOW     — day of week (1=Mon, 7=Sun)
#
# Supports: exact values, * (any), */N (every N), comma lists
# Returns: exit 0 if matches, exit 1 if not

EXPR="$1"
HOUR="${2:-$(date +%H)}"
MINUTE="${3:-$(date +%M)}"
DOW="${4:-$(date +%u)}"

# Parse the 5-field cron expression: MIN HOUR DOM MON DOW
read -r C_MIN C_HOUR C_DOM C_MON C_DOW <<< "$EXPR"

check_field() {
  local field="$1"
  local value="$((10#$2))"   # strip leading zeros

  # Wildcard
  [ "$field" = "*" ] && return 0

  # Every N: */5
  if [[ "$field" == */* ]]; then
    local divisor="${field#*/}"
    [ $(( value % divisor )) -eq 0 ] && return 0
    return 1
  fi

  # Comma list: 1,3,5
  IFS=',' read -ra PARTS <<< "$field"
  for part in "${PARTS[@]}"; do
    # Range: 1-5
    if [[ "$part" == *-* ]]; then
      local lo="${part%-*}"
      local hi="${part#*-}"
      [ "$value" -ge "$lo" ] && [ "$value" -le "$hi" ] && return 0
    elif [ "$value" -eq "$part" ]; then
      return 0
    fi
  done

  return 1
}

check_field "$C_MIN"  "$MINUTE" || exit 1
check_field "$C_HOUR" "$HOUR"   || exit 1
check_field "$C_DOW"  "$DOW"    || exit 1

exit 0
