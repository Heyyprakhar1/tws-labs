. "$LAB_LIB"

BASE="tcp-incident"
CONFIG="$BASE/config/api.env"
[ -f "$CONFIG" ] || fail "Configuration $CONFIG does not exist."

PORT=$(grep -E '^[[:space:]]*PORT=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
BACKLOG=$(grep -E '^[[:space:]]*TCP_BACKLOG=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CONCURRENCY=$(grep -E '^[[:space:]]*WORKER_CONCURRENCY=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$PORT" ] || fail "PORT missing from config/api.env."
[ -n "$BACKLOG" ] && [ "$BACKLOG" -ge 128 ] 2>/dev/null || fail "TCP_BACKLOG must be >= 128 (got '$BACKLOG')."
[ -n "$CONCURRENCY" ] && [ "$CONCURRENCY" -ge 16 ] 2>/dev/null || fail "WORKER_CONCURRENCY must be >= 16 (got '$CONCURRENCY')."

PID_FILE="$BASE/var/run/api-server.pid"
[ -f "$PID_FILE" ] || fail "Service PID file missing."
PID=$(cat "$PID_FILE" | tr -d '[:space:]')
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null || fail "api-gateway daemon is not running."

SS_LINE=$(ss -lnt "sport = :$PORT" 2>/dev/null | grep -E ":$PORT[[:space:]]" | head -n1 || true)
[ -n "$SS_LINE" ] || fail "No listening socket found on 127.0.0.1:$PORT."

SEND_Q=$(echo "$SS_LINE" | awk '{print $3}')
[ -n "$SEND_Q" ] && [ "$SEND_Q" -ge 128 ] 2>/dev/null || fail "Listening socket Send-Q must be >= 128 (got '$SEND_Q')."
