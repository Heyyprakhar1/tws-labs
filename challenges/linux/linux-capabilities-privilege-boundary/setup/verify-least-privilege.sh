#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
mkdir -p "$TARGET_DIR/reports" "$TARGET_DIR/var/run"

cat << 'EOF' > "$TARGET_DIR/reports/capability-audit.env"
CAP_EFF_HEX=0000000000000000
CAP_BND_HEX=00000000a80425fb
EFFECTIVE_CAPABILITY_COUNT=0
UNPRIVILEGED_PORT_START=0
PORT_80_REQUIRES_CAP_NET_BIND=false
EOF

cat << EOF > "$TARGET_DIR/reports/dac-incident.env"
FAILING_PATH=/var/run/app.pid
DIRECTORY_OWNER=root
DIRECTORY_MODE=0755
CALLER_UID=$(id -u)
FAILURE_REASON=DAC_WRITE_DENIED_TO_NON_OWNER
PROPOSED_RESOLUTION=CONFIGURE_USER_OWNED_RUNTIME_DIR
EOF

cat << EOF > "$TARGET_DIR/config/daemon.env"
# Hardened Non-Root Microservice Configuration
SERVICE_PORT=8085
PID_FILE="$TARGET_DIR/var/run/app.pid"
SOCKET_PATH="$TARGET_DIR/var/run/app.sock"
LOG_FILE="$TARGET_DIR/var/log/app.log"
RUN_AS_USER="lab0"
EOF

"$TARGET_DIR/bin/service-daemon" start
