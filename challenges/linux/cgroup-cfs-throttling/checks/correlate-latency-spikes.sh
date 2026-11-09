#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
REPORT="$INCIDENT_DIR/reports/cfs-correlation.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/cfs-correlation.env not found."
    exit 1
fi

BASE_LATENCY_MS=$(grep '^BASE_LATENCY_MS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
SPIKE_LATENCY_MS=$(grep '^SPIKE_LATENCY_MS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CFS_PERIOD_MS=$(grep '^CFS_PERIOD_MS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
THROTTLE_CORRELATION=$(grep '^THROTTLE_CORRELATION=' "$REPORT" | cut -d= -f2- | tr -d ' "')

case "$BASE_LATENCY_MS" in
    4|4.*) ;;
    *)
        echo "Check failed: BASE_LATENCY_MS expected ~4, got '$BASE_LATENCY_MS'."
        exit 1
        ;;
esac

case "$SPIKE_LATENCY_MS" in
    104|104.*|105|105.*) ;;
    *)
        echo "Check failed: SPIKE_LATENCY_MS expected ~104, got '$SPIKE_LATENCY_MS'."
        exit 1
        ;;
esac

if [ "$CFS_PERIOD_MS" != "100" ]; then
    echo "Check failed: CFS_PERIOD_MS expected 100, got '$CFS_PERIOD_MS'."
    exit 1
fi

if [ "$THROTTLE_CORRELATION" != "PERIOD_QUOTA_EXHAUSTION" ]; then
    echo "Check failed: THROTTLE_CORRELATION expected PERIOD_QUOTA_EXHAUSTION, got '$THROTTLE_CORRELATION'."
    exit 1
fi

echo "Check passed: latency spike correlation with CFS period window confirmed."
exit 0
