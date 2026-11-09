#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
REPORT="$INCIDENT_DIR/reports/recovery-verification.env"
PID_FILE="$INCIDENT_DIR/var/run/indexer.pid"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/recovery-verification.env not found. Run ./bin/benchmark-latency."
    exit 1
fi

STATUS=$(grep '^BENCHMARK_STATUS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
P99=$(grep '^MEASURED_P99_MS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
THROTTLED=$(grep '^THROTTLED_PERIODS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
STATE=$(grep '^RECOVERY_STATE=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$STATUS" != "PASS" ]; then
    echo "Check failed: BENCHMARK_STATUS expected PASS, got '$STATUS'."
    exit 1
fi

if [ "$THROTTLED" != "0" ]; then
    echo "Check failed: THROTTLED_PERIODS expected 0, got '$THROTTLED'."
    exit 1
fi

if [ "$STATE" != "HEALTHY" ]; then
    echo "Check failed: RECOVERY_STATE expected HEALTHY, got '$STATE'."
    exit 1
fi

# Verify P99 < 15.0
IS_BELOW_15=$(awk -v val="$P99" 'BEGIN { if (val < 15.0) print "yes"; else print "no" }')
if [ "$IS_BELOW_15" != "yes" ]; then
    echo "Check failed: MEASURED_P99_MS ($P99) is not below 15.0 ms threshold."
    exit 1
fi

# Verify process is running
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Check failed: search-indexer daemon is not running."
    exit 1
fi

echo "Check passed: latency recovery verified with zero CFS throttling."
exit 0
