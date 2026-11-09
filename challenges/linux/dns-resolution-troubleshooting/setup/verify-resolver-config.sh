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

# 2. Complete Task 2 (remove poisoned entry)
HOSTS="$INCIDENT/etc/hosts"
if [ -f "$HOSTS" ]; then
  sed -i '/192\.0\.2\.1/d' "$HOSTS"
fi

# 3. Ensure Task 3 is incomplete (defective search domain)
RESOLV="$INCIDENT/etc/resolv.conf"
cat << 'EOF' > "$RESOLV"
# DNS resolver configuration
nameserver 10.0.0.53
search dev.corp
EOF

NSS="$INCIDENT/etc/nsswitch.conf"
if [ -f "$NSS" ]; then
  sed -i 's/^[[:space:]]*hosts:.*/hosts:      files dns/' "$NSS"
fi
