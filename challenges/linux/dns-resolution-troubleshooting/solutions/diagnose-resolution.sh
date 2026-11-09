#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="$BASE/dns-incident"
mkdir -p "$INCIDENT/reports"

cat << 'EOF' > "$INCIDENT/reports/resolution-triage.env"
HOSTNAME=db.internal.corp
EXPECTED_IP=10.0.2.15
ACTUAL_IP=192.0.2.1
RESOLUTION_SOURCE=files
ROOT_CAUSE=poisoned static host mapping in etc/hosts
EOF
