#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

RESOLV="dns-incident/etc/resolv.conf"
NSS="dns-incident/etc/nsswitch.conf"

[ -f "$RESOLV" ] || fail "Configuration file dns-incident/etc/resolv.conf not found."
[ -f "$NSS" ] || fail "Configuration file dns-incident/etc/nsswitch.conf not found."

# 1. Check nameserver 10.0.0.53 in resolv.conf
if ! grep -Eq '^[[:space:]]*nameserver[[:space:]]+10\.0\.0\.53([[:space:]]|$)' "$RESOLV"; then
  fail "nameserver 10.0.0.53 is not configured in dns-incident/etc/resolv.conf."
fi

# 2. Check search internal.corp in resolv.conf
if ! grep -Eq '^[[:space:]]*search[[:space:]]+.*internal\.corp([[:space:]]|$)' "$RESOLV"; then
  fail "search domain 'internal.corp' is not configured in dns-incident/etc/resolv.conf."
fi

# 3. Check NSS hosts order: must be files dns (files precedes dns)
NSS_LINE=$(grep -E '^[[:space:]]*hosts:[[:space:]]' "$NSS" 2>/dev/null | head -n1 || true)
[ -n "$NSS_LINE" ] || fail "hosts entry missing in dns-incident/etc/nsswitch.conf."

NSS_ORDER=$(echo "$NSS_LINE" | sed 's/^[[:space:]]*hosts:[[:space:]]*//' | sed 's/[[:space:]]*$//')
case "$NSS_ORDER" in
  "files dns")
    ;;
  *)
    fail "NSS hosts order must be 'files dns' (currently: '$NSS_ORDER')."
    ;;
esac

# 4. Behavioral check: short hostname 'db' must resolve via search domain
RESOLVE="dns-incident/bin/resolve-host"
[ -x "$RESOLVE" ] || fail "dns-incident/bin/resolve-host not found or not executable."

DB_SHORT_IP=$("$RESOLVE" --ip db 2>/dev/null || true)
[ "$DB_SHORT_IP" = "10.0.2.15" ] || fail "Short hostname 'db' failed to resolve to 10.0.2.15 via search domain."
