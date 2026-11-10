#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"
REPORT="$INCIDENT/reports/auth-triage.env"

[ -f "$REPORT" ] || fail "Report reports/auth-triage.env not found in $INCIDENT."

# Validate format: KEY=VALUE without spaces around '='
if grep -Eq '^[[:space:]]*[^=]+[[:space:]]+=' "$REPORT" || grep -Eq '=[[:space:]]+' "$REPORT"; then
  fail "Illegal whitespace around '=' in auth-triage.env."
fi

# Reject illegal metacharacters ($ ` & | ; < > !)
if grep -Eq '[\$`&|;<>\!]' "$REPORT"; then
  fail "auth-triage.env contains prohibited characters."
fi

CLIENT_KEY_PATH=$(grep -E '^[[:space:]]*CLIENT_KEY_PATH=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CLIENT_KEY_PERMS=$(grep -E '^[[:space:]]*CLIENT_KEY_PERMS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
SERVER_STRICTMODES_ERROR=$(grep -E '^[[:space:]]*SERVER_STRICTMODES_ERROR=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
PUBKEY_MATCH=$(grep -E '^[[:space:]]*PUBKEY_MATCH=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ROOT_CAUSE=$(grep -E '^[[:space:]]*ROOT_CAUSE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$CLIENT_KEY_PATH" ] || fail "CLIENT_KEY_PATH is required in auth-triage.env."
[ -n "$CLIENT_KEY_PERMS" ] || fail "CLIENT_KEY_PERMS is required in auth-triage.env."
[ -n "$SERVER_STRICTMODES_ERROR" ] || fail "SERVER_STRICTMODES_ERROR is required in auth-triage.env."
[ -n "$PUBKEY_MATCH" ] || fail "PUBKEY_MATCH is required in auth-triage.env."
[ -n "$ROOT_CAUSE" ] || fail "ROOT_CAUSE is required in auth-triage.env."

case "$CLIENT_KEY_PATH" in
  *client/.ssh/id_rsa) ;;
  *) fail "CLIENT_KEY_PATH must point to client/.ssh/id_rsa." ;;
esac

case "$CLIENT_KEY_PERMS" in
  0644|644) ;;
  *) fail "CLIENT_KEY_PERMS must record the initial permissions of the client key (0644)." ;;
esac

RAW_STRICT=$(echo "$SERVER_STRICTMODES_ERROR" | tr '[:upper:]' '[:lower:]')
if ! echo "$RAW_STRICT" | grep -Eq 'ownership|modes|permission|writable'; then
  fail "SERVER_STRICTMODES_ERROR must document the StrictModes ownership or permission error from auth.log."
fi

case "$PUBKEY_MATCH" in
  false|no|mismatch|none) ;;
  *) fail "PUBKEY_MATCH must be 'false' or 'mismatch' because authorized_keys initially has a mismatched key." ;;
esac

RAW_CAUSE=$(echo "$ROOT_CAUSE" | tr '[:upper:]' '[:lower:]')
if ! echo "$RAW_CAUSE" | grep -Eq 'perm|mode|key|strict|priv|pub|mismatch'; then
  fail "ROOT_CAUSE must identify the permissions and/or public key mismatch."
fi
