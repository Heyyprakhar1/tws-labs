. "$LAB_LIB"

BASE="spool-incident"
MARKER="$BASE/reports/verification.marker"
[ -f "$MARKER" ] || fail "Verification marker $MARKER does not exist. Run ./bin/verify-spool to verify recovery."

STATUS=$(grep -E '^[[:space:]]*VERIFICATION_STATUS=' "$MARKER" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
[ "$STATUS" = "PASSED" ] || fail "VERIFICATION_STATUS is not PASSED (got '$STATUS')."

CONFIG="$BASE/config/spooler.env"
[ -f "$CONFIG" ] || fail "Configuration file $CONFIG does not exist."

MAX_FILES=$(grep -E '^[[:space:]]*MAX_SPOOL_FILES=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
AUTO_PURGE=$(grep -E '^[[:space:]]*AUTO_PURGE_ENABLED=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$MAX_FILES" ] && [ "$MAX_FILES" -ge 5000 ] 2>/dev/null || fail "MAX_SPOOL_FILES must be >= 5000 (got '$MAX_FILES')."
[ "$AUTO_PURGE" = "true" ] || fail "AUTO_PURGE_ENABLED must be true (got '$AUTO_PURGE')."

PID_FILE="$BASE/var/run/spooler.pid"
[ -f "$PID_FILE" ] || fail "Spooler PID file missing."
PID=$(cat "$PID_FILE" | tr -d '[:space:]')
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null || fail "event-spooler daemon is not running."
