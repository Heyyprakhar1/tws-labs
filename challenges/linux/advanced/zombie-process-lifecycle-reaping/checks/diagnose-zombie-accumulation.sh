#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
REPORT="$INCIDENT_DIR/reports/zombie-triage.env"
PID_FILE="$INCIDENT_DIR/var/run/supervisor.pid"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/zombie-triage.env not found."
    exit 1
fi

SUPERVISOR_PID=$(grep '^SUPERVISOR_PID=' "$REPORT" | cut -d= -f2- | tr -d ' "')
ZOMBIE_COUNT=$(grep '^ZOMBIE_COUNT=' "$REPORT" | cut -d= -f2- | tr -d ' "')
PROCESS_STATE=$(grep '^PROCESS_STATE=' "$REPORT" | cut -d= -f2- | tr -d ' "')
REAPING_STATUS=$(grep '^REAPING_STATUS=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ -f "$PID_FILE" ]; then
    ACTUAL_PID=$(cat "$PID_FILE" | tr -d ' ')
    if [ "$SUPERVISOR_PID" != "$ACTUAL_PID" ]; then
        echo "Check failed: SUPERVISOR_PID ($SUPERVISOR_PID) does not match active supervisor PID ($ACTUAL_PID)."
        exit 1
    fi
fi

if [ "$ZOMBIE_COUNT" != "10" ]; then
    echo "Check failed: ZOMBIE_COUNT expected 10, got '$ZOMBIE_COUNT'."
    exit 1
fi

if [ "$PROCESS_STATE" != "Z" ]; then
    echo "Check failed: PROCESS_STATE expected Z, got '$PROCESS_STATE'."
    exit 1
fi

if [ "$REAPING_STATUS" != "DEFUNCT_ACCUMULATION" ]; then
    echo "Check failed: REAPING_STATUS expected DEFUNCT_ACCUMULATION, got '$REAPING_STATUS'."
    exit 1
fi

echo "Check passed: zombie process accumulation and supervisor PID diagnosed."
exit 0
