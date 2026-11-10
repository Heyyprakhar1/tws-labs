#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
CONF_FILE="$INCIDENT_DIR/config/indexer.cgroup"
MAX_FILE="$INCIDENT_DIR/telemetry/cgroup/cpu.max"
PID_FILE="$INCIDENT_DIR/var/run/indexer.pid"

if [ ! -f "$CONF_FILE" ]; then
    echo "Check failed: config/indexer.cgroup not found."
    exit 1
fi

LINE=$(grep '^cpu.max:' "$CONF_FILE" | head -n1)
if [ -z "$LINE" ]; then
    echo "Check failed: cpu.max directive not found in config/indexer.cgroup."
    exit 1
fi

QUOTA=$(echo "$LINE" | awk '{print $2}')
PERIOD=$(echo "$LINE" | awk '{print $3}')

if [ "$QUOTA" = "25000" ]; then
    echo "Check failed: cpu.max quota is still 25000 (restricted). Needs to be raised to at least 100000."
    exit 1
fi

# Quota must be at least 100000 or 'max'
if [ "$QUOTA" != "max" ]; then
    if ! [[ "$QUOTA" =~ ^[0-9]+$ ]] || [ "$QUOTA" -lt 100000 ]; then
        echo "Check failed: cpu.max quota ($QUOTA) is less than recommended 100000."
        exit 1
    fi
fi

# Check that service is alive
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Check failed: search-indexer daemon is not running. Did you restart the service?"
    exit 1
fi

# Check telemetry cpu.max reflects new quota
if [ -f "$MAX_FILE" ]; then
    CURRENT_MAX=$(cat "$MAX_FILE" | awk '{print $1}')
    if [ "$CURRENT_MAX" = "25000" ]; then
        echo "Check failed: telemetry/cgroup/cpu.max still shows old quota 25000. Run ./bin/search-ctl restart."
        exit 1
    fi
fi

echo "Check passed: CPU quota reconfigured and search-indexer service running with updated limits."
exit 0
