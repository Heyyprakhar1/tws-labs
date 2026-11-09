#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/cfs-correlation.env" <<'EOF'
BASE_LATENCY_MS=4
SPIKE_LATENCY_MS=104
CFS_PERIOD_MS=100
THROTTLE_CORRELATION=PERIOD_QUOTA_EXHAUSTION
EOF
