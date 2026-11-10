#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

HOSTS="dns-incident/etc/hosts"
[ -f "$HOSTS" ] || fail "Configuration file dns-incident/etc/hosts not found."

# 1. 192.0.2.1 must be removed
if grep -qE '^[[:space:]]*192\.0\.2\.1(\s|$)' "$HOSTS"; then
  fail "Poisoned IP 192.0.2.1 is still present in dns-incident/etc/hosts."
fi

# 2. db.internal.corp must not point to any IP other than 10.0.2.15 in hosts
if grep -qE '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+.*db\.internal\.corp' "$HOSTS"; then
  MAPPED_IP=$(awk '/db\.internal\.corp/ { print $1 }' "$HOSTS" | head -n1)
  if [ "$MAPPED_IP" != "10.0.2.15" ]; then
    fail "db.internal.corp in dns-incident/etc/hosts is still mapped to incorrect IP ($MAPPED_IP)."
  fi
fi

# 3. localhost entry must be preserved
if ! grep -qE '^[[:space:]]*127\.0\.0\.1[[:space:]]+.*localhost' "$HOSTS"; then
  fail "localhost entry (127.0.0.1) missing from dns-incident/etc/hosts."
fi

# 4. resolve-host must not return 192.0.2.1
RESOLVE="dns-incident/bin/resolve-host"
[ -x "$RESOLVE" ] || fail "dns-incident/bin/resolve-host not found or not executable."

CURRENT_IP=$("$RESOLVE" --ip db.internal.corp 2>/dev/null || true)
if [ "$CURRENT_IP" = "192.0.2.1" ]; then
  fail "resolve-host still returns poisoned address 192.0.2.1 for db.internal.corp."
fi
