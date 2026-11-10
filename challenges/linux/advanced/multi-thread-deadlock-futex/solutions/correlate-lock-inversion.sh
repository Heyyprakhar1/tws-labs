#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
REPORT_FILE="$BASE_DIR/reports/inversion-analysis.env"
mkdir -p "$BASE_DIR/reports"

cat << 'EOF' > "$REPORT_FILE"
INVERSION_TYPE=AB_BA_LOCK_INVERSION
THREAD_1_HOLDS=MUTEX_A
THREAD_1_WAITS=MUTEX_B
THREAD_2_HOLDS=MUTEX_B
THREAD_2_WAITS=MUTEX_A
RESOLUTION_STRATEGY=ORDERED_RESOURCE_ACQUISITION
EOF

echo "Analysis report saved to $REPORT_FILE"
