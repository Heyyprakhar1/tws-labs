#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/dag-analysis.env" <<'EOF'
ORDERING_DIRECTIVES="After,Before"
REQUIREMENT_DIRECTIVES="Requires,Wants"
DEFECTIVE_UNIT="payment-auth.service"
DEFECTIVE_DIRECTIVE="After=payment-api.service"
RESOLUTION="REMOVE_ORDERING_EDGE"
EOF
