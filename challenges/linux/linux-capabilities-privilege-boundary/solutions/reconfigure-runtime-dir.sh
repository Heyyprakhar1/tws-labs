#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
mkdir -p "$TARGET_DIR/var/run"

cat << EOF > "$TARGET_DIR/config/daemon.env"
# Hardened Non-Root Microservice Configuration
SERVICE_PORT=8085
PID_FILE="$TARGET_DIR/var/run/app.pid"
SOCKET_PATH="$TARGET_DIR/var/run/app.sock"
LOG_FILE="$TARGET_DIR/var/log/app.log"
RUN_AS_USER="lab0"
EOF
