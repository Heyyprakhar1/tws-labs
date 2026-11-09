#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/cycle-triage.env" <<'EOF'
CYCLE_DETECTED=true
CYCLE_UNITS="payment-api.service,payment-cache.service,payment-auth.service"
CYCLE_LENGTH=3
CONFLICTING_DIRECTIVE=After
EOF
