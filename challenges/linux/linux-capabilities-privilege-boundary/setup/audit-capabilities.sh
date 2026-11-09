#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
mkdir -p "$TARGET_DIR/reports"

cat << 'EOF' > "$TARGET_DIR/reports/capability-audit.env"
CAP_EFF_HEX=0000000000000000
CAP_BND_HEX=00000000a80425fb
EFFECTIVE_CAPABILITY_COUNT=0
UNPRIVILEGED_PORT_START=0
PORT_80_REQUIRES_CAP_NET_BIND=false
EOF
