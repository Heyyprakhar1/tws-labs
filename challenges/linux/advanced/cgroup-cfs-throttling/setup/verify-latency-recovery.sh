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

cat > "$INCIDENT_DIR/reports/cfs-correlation.env" <<'EOF'
BASE_LATENCY_MS=4
SPIKE_LATENCY_MS=104
CFS_PERIOD_MS=100
THROTTLE_CORRELATION=PERIOD_QUOTA_EXHAUSTION
EOF

cat > "$INCIDENT_DIR/config/indexer.cgroup" <<'EOF'
# Cgroup v2 CPU Bandwidth Configuration
cpu.max: 100000 100000
EOF

"$INCIDENT_DIR/bin/search-ctl" restart
sleep 0.3
"$INCIDENT_DIR/bin/benchmark-latency"
