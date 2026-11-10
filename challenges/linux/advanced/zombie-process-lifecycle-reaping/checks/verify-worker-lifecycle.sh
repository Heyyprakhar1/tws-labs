#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
REPORT="$INCIDENT_DIR/reports/recovery-report.env"
PID_FILE="$INCIDENT_DIR/var/run/supervisor.pid"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/recovery-report.env not found. Run ./bin/verify-reaping."
    exit 1
fi

STATUS=$(grep '^VERIFICATION_STATUS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
DISPATCHED=$(grep '^WORKERS_DISPATCHED=' "$REPORT" | cut -d= -f2- | tr -d ' "')
REAPED=$(grep '^WORKERS_REAPED=' "$REPORT" | cut -d= -f2- | tr -d ' "')
ACTIVE_ZOMBIES=$(grep '^ACTIVE_ZOMBIES=' "$REPORT" | cut -d= -f2- | tr -d ' "')
REAPER_ACTIVE=$(grep '^REAPER_ACTIVE=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$STATUS" != "SUCCESS" ]; then
    echo "Check failed: VERIFICATION_STATUS expected SUCCESS, got '$STATUS'."
    exit 1
fi

if [ "$DISPATCHED" != "10" ]; then
    echo "Check failed: WORKERS_DISPATCHED expected 10, got '$DISPATCHED'."
    exit 1
fi

if [ "$REAPED" != "10" ]; then
    echo "Check failed: WORKERS_REAPED expected 10, got '$REAPED'."
    exit 1
fi

if [ "$ACTIVE_ZOMBIES" != "0" ]; then
    echo "Check failed: ACTIVE_ZOMBIES expected 0, got '$ACTIVE_ZOMBIES'."
    exit 1
fi

if [ "$REAPER_ACTIVE" != "true" ]; then
    echo "Check failed: REAPER_ACTIVE expected true, got '$REAPER_ACTIVE'."
    exit 1
fi

# Live check: verify supervisor is running and 0 zombies exist
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Check failed: batch-supervisor daemon is not running."
    exit 1
fi

SUP_PID=$(cat "$PID_FILE")
LIVE_ZOMBIES=$(ps -o pid,ppid,stat,cmd -u "$UID" 2>/dev/null | awk -v ppid="$SUP_PID" '$2 == ppid && $3 ~ /Z/ { count++ } END { print count+0 }')

if [ "$LIVE_ZOMBIES" -ne 0 ]; then
    echo "Check failed: $LIVE_ZOMBIES defunct zombie processes still detected in live process table."
    exit 1
fi

echo "Check passed: worker lifecycle and clean SIGCHLD reaping verified."
exit 0
