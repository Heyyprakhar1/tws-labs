#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
REPORT="$INCIDENT_DIR/reports/pmtu-analysis.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/pmtu-analysis.env not found."
    exit 1
fi

TUNNEL_MTU=$(grep '^TUNNEL_MTU=' "$REPORT" | cut -d= -f2- | tr -d ' "')
IPV4_HEADER_BYTES=$(grep '^IPV4_HEADER_BYTES=' "$REPORT" | cut -d= -f2- | tr -d ' "')
TCP_HEADER_BYTES=$(grep '^TCP_HEADER_BYTES=' "$REPORT" | cut -d= -f2- | tr -d ' "')
TOTAL_HEADER_OVERHEAD=$(grep '^TOTAL_HEADER_OVERHEAD=' "$REPORT" | cut -d= -f2- | tr -d ' "')
OPTIMAL_MSS=$(grep '^OPTIMAL_MSS=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$TUNNEL_MTU" != "1420" ]; then
    echo "Check failed: TUNNEL_MTU expected 1420, got '$TUNNEL_MTU'."
    exit 1
fi

if [ "$IPV4_HEADER_BYTES" != "20" ]; then
    echo "Check failed: IPV4_HEADER_BYTES expected 20, got '$IPV4_HEADER_BYTES'."
    exit 1
fi

if [ "$TCP_HEADER_BYTES" != "20" ]; then
    echo "Check failed: TCP_HEADER_BYTES expected 20, got '$TCP_HEADER_BYTES'."
    exit 1
fi

if [ "$TOTAL_HEADER_OVERHEAD" != "40" ]; then
    echo "Check failed: TOTAL_HEADER_OVERHEAD expected 40, got '$TOTAL_HEADER_OVERHEAD'."
    exit 1
fi

if [ "$OPTIMAL_MSS" != "1380" ]; then
    echo "Check failed: OPTIMAL_MSS expected 1380 (1420 - 40), got '$OPTIMAL_MSS'."
    exit 1
fi

echo "Check passed: optimal TCP MSS clamping calculation verified."
exit 0
