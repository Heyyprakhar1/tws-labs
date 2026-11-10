#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
mkdir -p "$TARGET_DIR/reports"

cat << 'EOF' > "$TARGET_DIR/reports/root-cause.env"
FAULTING_FUNCTION=process_batch
VULNERABLE_STRUCT_MEMBER=telemetry_endpoint
ROOT_CAUSE=UNCHECKED_NULL_POINTER_DEREFERENCE
TRIGGERING_CONFIG_KEY=TELEMETRY_ENDPOINT
EOF
