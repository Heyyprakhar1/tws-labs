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

cat > "$INCIDENT_DIR/reports/dag-analysis.env" <<'EOF'
ORDERING_DIRECTIVES="After,Before"
REQUIREMENT_DIRECTIVES="Requires,Wants"
DEFECTIVE_UNIT="payment-auth.service"
DEFECTIVE_DIRECTIVE="After=payment-api.service"
RESOLUTION="REMOVE_ORDERING_EDGE"
EOF

sed -i '/After=payment-api.service/d' "$INCIDENT_DIR/config/units/payment-auth.service"
