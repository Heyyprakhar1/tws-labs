#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
HOSTS="$BASE/dns-incident/etc/hosts"

if [ -f "$HOSTS" ]; then
  sed -i '/192\.0\.2\.1/d' "$HOSTS"
fi
