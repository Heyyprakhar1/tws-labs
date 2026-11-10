#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/pmtu-analysis.env" <<'EOF'
TUNNEL_MTU=1420
IPV4_HEADER_BYTES=20
TCP_HEADER_BYTES=20
TOTAL_HEADER_OVERHEAD=40
OPTIMAL_MSS=1380
EOF
