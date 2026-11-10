#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
REPORT="$INCIDENT_DIR/reports/recovery-report.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/recovery-report.env not found. Run ./bin/verify-transfer."
    exit 1
fi

STATUS=$(grep '^TRANSFER_STATUS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
SEGMENTS=$(grep '^SEGMENTS_TRANSMITTED=' "$REPORT" | cut -d= -f2- | tr -d ' "')
MSS=$(grep '^MAX_SEGMENT_SIZE=' "$REPORT" | cut -d= -f2- | tr -d ' "')
FRAME=$(grep '^EFFECTIVE_FRAME_SIZE=' "$REPORT" | cut -d= -f2- | tr -d ' "')
LOSS=$(grep '^PACKET_LOSS_COUNT=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$STATUS" != "SUCCESS" ]; then
    echo "Check failed: TRANSFER_STATUS expected SUCCESS, got '$STATUS'."
    exit 1
fi

if [ "$LOSS" != "0" ]; then
    echo "Check failed: PACKET_LOSS_COUNT expected 0, got '$LOSS'."
    exit 1
fi

if [ "$MSS" -gt 1380 ]; then
    echo "Check failed: MAX_SEGMENT_SIZE ($MSS) exceeds 1380."
    exit 1
fi

if [ "$FRAME" -gt 1420 ]; then
    echo "Check failed: EFFECTIVE_FRAME_SIZE ($FRAME) exceeds tunnel MTU 1420."
    exit 1
fi

echo "Check passed: bulk database replication transfer recovery verified across tunnel."
exit 0
