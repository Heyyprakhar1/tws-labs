#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/cfs-triage.env" <<'EOF'
CFS_PERIOD_US=100000
CFS_QUOTA_US=25000
NR_PERIODS=1500
NR_THROTTLED=980
THROTTLED_RATIO=65.3
EOF
