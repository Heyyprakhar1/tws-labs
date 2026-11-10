#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
REPORT="$INCIDENT_DIR/reports/pmtu-triage.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/pmtu-triage.env not found."
    exit 1
fi

NEGOTIATED_MSS=$(grep '^NEGOTIATED_MSS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
DROPPED_FRAME_SIZE=$(grep '^DROPPED_FRAME_SIZE=' "$REPORT" | cut -d= -f2- | tr -d ' "')
DF_BIT_SET=$(grep '^DF_BIT_SET=' "$REPORT" | cut -d= -f2- | tr -d ' "')
ICMP_FEEDBACK_COUNT=$(grep '^ICMP_FEEDBACK_COUNT=' "$REPORT" | cut -d= -f2- | tr -d ' "')
FAILURE_MODE=$(grep '^FAILURE_MODE=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$NEGOTIATED_MSS" != "1460" ]; then
    echo "Check failed: NEGOTIATED_MSS expected 1460, got '$NEGOTIATED_MSS'."
    exit 1
fi

if [ "$DROPPED_FRAME_SIZE" != "1500" ]; then
    echo "Check failed: DROPPED_FRAME_SIZE expected 1500, got '$DROPPED_FRAME_SIZE'."
    exit 1
fi

if [ "$DF_BIT_SET" != "true" ]; then
    echo "Check failed: DF_BIT_SET expected true, got '$DF_BIT_SET'."
    exit 1
fi

if [ "$ICMP_FEEDBACK_COUNT" != "0" ]; then
    echo "Check failed: ICMP_FEEDBACK_COUNT expected 0, got '$ICMP_FEEDBACK_COUNT'."
    exit 1
fi

if [ "$FAILURE_MODE" != "PMTU_BLACK_HOLE" ]; then
    echo "Check failed: FAILURE_MODE expected PMTU_BLACK_HOLE, got '$FAILURE_MODE'."
    exit 1
fi

echo "Check passed: PMTU black hole forensic evidence verified."
exit 0
