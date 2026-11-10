#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="$BASE/dns-incident"

RESOLV="$INCIDENT/etc/resolv.conf"
NSS="$INCIDENT/etc/nsswitch.conf"

# Configure resolv.conf
cat << 'EOF' > "$RESOLV"
# DNS resolver configuration
nameserver 10.0.0.53
search internal.corp
EOF

# Ensure nsswitch.conf has hosts: files dns
if [ -f "$NSS" ]; then
  sed -i 's/^[[:space:]]*hosts:.*/hosts:      files dns/' "$NSS"
fi
