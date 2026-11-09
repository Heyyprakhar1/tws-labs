#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
ENV_FILE="$INCIDENT_DIR/config/supervisor.env"
PID_FILE="$INCIDENT_DIR/var/run/supervisor.pid"

if [ ! -f "$ENV_FILE" ]; then
    echo "Check failed: config/supervisor.env not found."
    exit 1
fi

REAPER_ENABLED=$(grep '^ENABLE_SIGCHLD_REAPER=' "$ENV_FILE" | cut -d= -f2- | tr -d ' "')
if [ "$REAPER_ENABLED" != "true" ]; then
    echo "Check failed: ENABLE_SIGCHLD_REAPER is '$REAPER_ENABLED', expected 'true'."
    exit 1
fi

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Check failed: batch-supervisor daemon is not running. Did you restart the service?"
    exit 1
fi

# Check defunct process count in process table
SUP_PID=$(cat "$PID_FILE")
ZOMBIE_COUNT=$(ps -o pid,ppid,stat,cmd -u "$UID" 2>/dev/null | awk -v ppid="$SUP_PID" '$2 == ppid && $3 ~ /Z/ { count++ } END { print count+0 }')

if [ "$ZOMBIE_COUNT" -ne 0 ]; then
    echo "Check failed: $ZOMBIE_COUNT defunct zombie processes still detected in process table."
    exit 1
fi

echo "Check passed: SIGCHLD reaper active and defunct zombie processes eliminated."
exit 0
