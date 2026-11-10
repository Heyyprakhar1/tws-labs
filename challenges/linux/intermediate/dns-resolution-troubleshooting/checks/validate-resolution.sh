#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

INCIDENT="dns-incident"
MARKER="$INCIDENT/.resolution-validated"
[ -f "$MARKER" ] || fail "Validation marker missing. Run ./dns-incident/bin/validate-resolution to complete verification."

RESOLVE="$INCIDENT/bin/resolve-host"
DIG="$INCIDENT/bin/dig-dns"

# Independent behavioral checks
DB_IP=$("$RESOLVE" --ip db.internal.corp 2>/dev/null || true)
[ "$DB_IP" = "10.0.2.15" ] || fail "db.internal.corp must resolve to 10.0.2.15 (got '$DB_IP')."

API_IP=$("$RESOLVE" --ip api.internal.corp 2>/dev/null || true)
[ "$API_IP" = "10.0.2.20" ] || fail "api.internal.corp must resolve to 10.0.2.20 (got '$API_IP')."

SHORT_IP=$("$RESOLVE" --ip db 2>/dev/null || true)
[ "$SHORT_IP" = "10.0.2.15" ] || fail "Short hostname 'db' must resolve to 10.0.2.15 (got '$SHORT_IP')."

LO_IP=$("$RESOLVE" --ip localhost 2>/dev/null || true)
[ "$LO_IP" = "127.0.0.1" ] || fail "localhost must resolve to 127.0.0.1 (got '$LO_IP')."

# Direct DNS checks
DIG_DB=$("$DIG" +short db.internal.corp 2>/dev/null || true)
[ "$DIG_DB" = "10.0.2.15" ] || fail "Direct DNS for db.internal.corp must return 10.0.2.15."

DIG_API=$("$DIG" +short api.internal.corp 2>/dev/null || true)
[ "$DIG_API" = "10.0.2.20" ] || fail "Direct DNS for api.internal.corp must return 10.0.2.20."

# Anti-cheat / regression: ensure poisoned address is gone from hosts
if grep -qE '^[[:space:]]*192\.0\.2\.1(\s|$)' "$INCIDENT/etc/hosts" 2>/dev/null; then
  fail "Poisoned IP 192.0.2.1 is still present in dns-incident/etc/hosts."
fi
