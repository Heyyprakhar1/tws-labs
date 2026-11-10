#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
REPORT="$INCIDENT_DIR/reports/cfs-triage.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/cfs-triage.env not found."
    exit 1
fi

CFS_PERIOD_US=$(grep '^CFS_PERIOD_US=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CFS_QUOTA_US=$(grep '^CFS_QUOTA_US=' "$REPORT" | cut -d= -f2- | tr -d ' "')
NR_PERIODS=$(grep '^NR_PERIODS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
NR_THROTTLED=$(grep '^NR_THROTTLED=' "$REPORT" | cut -d= -f2- | tr -d ' "')
THROTTLED_RATIO=$(grep '^THROTTLED_RATIO=' "$REPORT" | cut -d= -f2- | tr -d ' "%')

if [ "$CFS_PERIOD_US" != "100000" ]; then
    echo "Check failed: CFS_PERIOD_US expected 100000, got '$CFS_PERIOD_US'."
    exit 1
fi

if [ "$CFS_QUOTA_US" != "25000" ]; then
    echo "Check failed: CFS_QUOTA_US expected 25000, got '$CFS_QUOTA_US'."
    exit 1
fi

if [ "$NR_PERIODS" != "1500" ]; then
    echo "Check failed: NR_PERIODS expected 1500, got '$NR_PERIODS'."
    exit 1
fi

if [ "$NR_THROTTLED" != "980" ]; then
    echo "Check failed: NR_THROTTLED expected 980, got '$NR_THROTTLED'."
    exit 1
fi

# Accept 65.3 or 65.33
case "$THROTTLED_RATIO" in
    65.3*|65.33*) ;;
    *)
        echo "Check failed: THROTTLED_RATIO expected 65.3, got '$THROTTLED_RATIO'."
        exit 1
        ;;
esac

echo "Check passed: cgroup v2 CFS bandwidth throttling correctly diagnosed."
exit 0
