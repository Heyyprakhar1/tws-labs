#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"

cat > "$INCIDENT_DIR/config/indexer.cgroup" <<'EOF'
# Cgroup v2 CPU Bandwidth Configuration
# 100000 100000 = 1.0 CPU core (100ms quota per 100ms period)
cpu.max: 100000 100000
EOF

"$INCIDENT_DIR/bin/search-ctl" restart
