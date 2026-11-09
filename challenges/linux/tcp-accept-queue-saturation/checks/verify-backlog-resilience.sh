. "$LAB_LIB"

BASE="tcp-incident"
MARKER="$BASE/reports/verification.marker"
[ -f "$MARKER" ] || fail "Verification marker $MARKER missing. Run ./bin/verify-backlog to complete audit."

STATUS=$(grep -E '^[[:space:]]*VERIFICATION_STATUS=' "$MARKER" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
[ "$STATUS" = "PASSED" ] || fail "VERIFICATION_STATUS is not PASSED (got '$STATUS')."

CONFIG="$BASE/config/api.env"
[ -f "$CONFIG" ] || fail "Configuration $CONFIG missing."
BACKLOG=$(grep -E '^[[:space:]]*TCP_BACKLOG=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
[ -n "$BACKLOG" ] && [ "$BACKLOG" -ge 128 ] 2>/dev/null || fail "TCP_BACKLOG must be >= 128 (got '$BACKLOG')."

PID_FILE="$BASE/var/run/api-server.pid"
[ -f "$PID_FILE" ] || fail "Service PID file missing."
PID=$(cat "$PID_FILE" | tr -d '[:space:]')
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null || fail "api-gateway daemon is not running."
