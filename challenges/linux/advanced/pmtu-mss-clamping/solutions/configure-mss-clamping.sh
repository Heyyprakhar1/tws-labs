#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"

# 1. Update config/gateway.env
sed -i 's/^MSS_CLAMPING=.*/MSS_CLAMPING="enabled"/' "$INCIDENT_DIR/config/gateway.env"
sed -i 's/^TCP_MSS=.*/TCP_MSS=1380/' "$INCIDENT_DIR/config/gateway.env"

# 2. Update config/iptables-rules.sh
cat >> "$INCIDENT_DIR/config/iptables-rules.sh" <<'EOF'
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o gre0 -j TCPMSS --set-mss 1380
EOF
