#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
mkdir -p "$TARGET_DIR/reports"

cat << EOF > "$TARGET_DIR/reports/dac-incident.env"
FAILING_PATH=/var/run/app.pid
DIRECTORY_OWNER=root
DIRECTORY_MODE=0755
CALLER_UID=$(id -u)
FAILURE_REASON=DAC_WRITE_DENIED_TO_NON_OWNER
PROPOSED_RESOLUTION=CONFIGURE_USER_OWNED_RUNTIME_DIR
EOF
