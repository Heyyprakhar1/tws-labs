#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/pmtu-triage.env" <<'EOF'
NEGOTIATED_MSS=1460
DROPPED_FRAME_SIZE=1500
DF_BIT_SET=true
ICMP_FEEDBACK_COUNT=0
FAILURE_MODE=PMTU_BLACK_HOLE
EOF
