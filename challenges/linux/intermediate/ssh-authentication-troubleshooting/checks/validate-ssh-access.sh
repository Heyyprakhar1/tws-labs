#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

VALIDATED_MARKER="$INCIDENT/.ssh-validated"
[ -f "$VALIDATED_MARKER" ] || fail "Validation marker $VALIDATED_MARKER not found. Run ./bin/verify-ssh to validate."

grep -Eq '^AUTH_RESULT=SUCCESS' "$VALIDATED_MARKER" || fail "Validation marker does not record AUTH_RESULT=SUCCESS."
grep -Eq '^OPENSSL_VERIFIED=PASS' "$VALIDATED_MARKER" || fail "Validation marker does not record OPENSSL_VERIFIED=PASS."

# Run simulated connection test directly
CONN_OUT=$("$INCIDENT/bin/ssh-connect" 2>&1)
CONN_RC=$?

[ "$CONN_RC" -eq 0 ] || fail "Simulated connection failed with exit code $CONN_RC: $CONN_OUT"
echo "$CONN_OUT" | grep -Fq "Authenticated to internal-srv" || fail "Connection did not authenticate successfully to internal-srv."
