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

cat > "$INCIDENT_DIR/reports/pmtu-analysis.env" <<'EOF'
TUNNEL_MTU=1420
IPV4_HEADER_BYTES=20
TCP_HEADER_BYTES=20
TOTAL_HEADER_OVERHEAD=40
OPTIMAL_MSS=1380
EOF

sed -i 's/^MSS_CLAMPING=.*/MSS_CLAMPING="enabled"/' "$INCIDENT_DIR/config/gateway.env"
sed -i 's/^TCP_MSS=.*/TCP_MSS=1380/' "$INCIDENT_DIR/config/gateway.env"

cat >> "$INCIDENT_DIR/config/iptables-rules.sh" <<'EOF'
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o gre0 -j TCPMSS --set-mss 1380
EOF

"$INCIDENT_DIR/bin/verify-transfer"
