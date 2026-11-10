#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

REPORT="dns-incident/reports/resolution-triage.env"
[ -f "$REPORT" ] || fail "Report dns-incident/reports/resolution-triage.env not found."

# Validate format: KEY=VALUE without spaces around '='
if grep -Eq '^[[:space:]]*[^=]+[[:space:]]+=' "$REPORT" || grep -Eq '=[[:space:]]+' "$REPORT"; then
  fail "Illegal whitespace around '=' in resolution-triage.env."
fi

# Reject illegal metacharacters ($ ` & | ; < > !)
if grep -Eq '[\$`&|;<>\!]' "$REPORT"; then
  fail "resolution-triage.env contains prohibited characters."
fi

HOSTNAME=$(grep -E '^[[:space:]]*HOSTNAME=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
EXPECTED_IP=$(grep -E '^[[:space:]]*EXPECTED_IP=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ACTUAL_IP=$(grep -E '^[[:space:]]*ACTUAL_IP=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
RESOLUTION_SOURCE=$(grep -E '^[[:space:]]*RESOLUTION_SOURCE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ROOT_CAUSE=$(grep -E '^[[:space:]]*ROOT_CAUSE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$HOSTNAME" ] || fail "HOSTNAME is required in resolution-triage.env."
[ -n "$EXPECTED_IP" ] || fail "EXPECTED_IP is required in resolution-triage.env."
[ -n "$ACTUAL_IP" ] || fail "ACTUAL_IP is required in resolution-triage.env."
[ -n "$RESOLUTION_SOURCE" ] || fail "RESOLUTION_SOURCE is required in resolution-triage.env."
[ -n "$ROOT_CAUSE" ] || fail "ROOT_CAUSE is required in resolution-triage.env."

[ "$HOSTNAME" = "db.internal.corp" ] || fail "HOSTNAME must be 'db.internal.corp'."
[ "$EXPECTED_IP" = "10.0.2.15" ] || fail "EXPECTED_IP must be '10.0.2.15' (from direct DNS)."
[ "$ACTUAL_IP" = "192.0.2.1" ] || fail "ACTUAL_IP must be '192.0.2.1' (from normal resolution)."

case "$RESOLUTION_SOURCE" in
  files|etc/hosts|hosts)
    ;;
  *)
    fail "RESOLUTION_SOURCE must be 'files' (the NSS source returning the incorrect IP)."
    ;;
esac

RAW_CAUSE=$(grep -E '^[[:space:]]*ROOT_CAUSE=' "$REPORT" | head -n1 | cut -d= -f2- | tr '[:upper:]' '[:lower:]')
if ! echo "$RAW_CAUSE" | grep -Eq 'poison|host|static|override'; then
  fail "ROOT_CAUSE must identify the poisoned static host mapping as the cause."
fi
