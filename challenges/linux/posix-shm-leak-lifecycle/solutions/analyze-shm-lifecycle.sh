#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
REPORT_FILE="$BASE_DIR/reports/lifecycle-analysis.env"

mkdir -p "$BASE_DIR/reports"

cat << 'EOF' > "$REPORT_FILE"
UNLINK_REMOVES_NAME=true
UNLINK_FREES_MAPPING_IMMEDIATELY=false
KERNEL_MAPS_STATUS=DELETED
RECLAMATION_CONDITION=LAST_REFERENCE_CLOSED
EOF

echo "Lifecycle analysis report saved to $REPORT_FILE"
