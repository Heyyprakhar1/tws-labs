#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="$BASE/dns-incident"

# 1. Complete Task 1
mkdir -p "$INCIDENT/reports"
cat << 'EOF' > "$INCIDENT/reports/resolution-triage.env"
HOSTNAME=db.internal.corp
EXPECTED_IP=10.0.2.15
ACTUAL_IP=192.0.2.1
RESOLUTION_SOURCE=files
ROOT_CAUSE=poisoned static host mapping in etc/hosts
EOF

# 2. Ensure Task 2 is incomplete (re-insert poisoned entry if missing)
HOSTS="$INCIDENT/etc/hosts"
if [ -f "$HOSTS" ] && ! grep -q "192.0.2.1" "$HOSTS"; then
  echo "192.0.2.1 db.internal.corp db" >> "$HOSTS"
fi
