BASE="$HOME/tcp-incident"
CONFIG="$BASE/config/api.env"

if [ ! -f "$CONFIG" ]; then
  echo "Error: Configuration $CONFIG not found" >&2
  exit 1
fi

PORT=$(grep -E '^[[:space:]]*PORT=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
BACKLOG=$(grep -E '^[[:space:]]*TCP_BACKLOG=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

if [ -z "$PORT" ] || ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid or missing PORT in $CONFIG" >&2
  exit 1
fi

if [ -z "$BACKLOG" ] || ! [[ "$BACKLOG" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid or missing TCP_BACKLOG in $CONFIG" >&2
  exit 1
fi

SS_LINE=$(ss -lnt "sport = :$PORT" 2>/dev/null | grep -E ":$PORT\b" | head -n1 || true)
if [ -z "$SS_LINE" ]; then
  SS_LINE=$(ss -lnt 2>/dev/null | grep -E ":$PORT\b" | head -n1 || true)
fi

if [ -z "$SS_LINE" ]; then
  echo "Error: No listening socket found on port $PORT" >&2
  exit 1
fi

RECV_Q=$(echo "$SS_LINE" | awk '{print $2}')
SEND_Q=$(echo "$SS_LINE" | awk '{print $3}')

if [ -z "$RECV_Q" ] || ! [[ "$RECV_Q" =~ ^[0-9]+$ ]]; then
  echo "Error: Failed to parse Recv-Q from socket state: '$SS_LINE'" >&2
  exit 1
fi

if [ -z "$SEND_Q" ] || ! [[ "$SEND_Q" =~ ^[0-9]+$ ]]; then
  echo "Error: Failed to parse Send-Q from socket state: '$SS_LINE'" >&2
  exit 1
fi

if [ "$RECV_Q" -lt "$SEND_Q" ]; then
  echo "Error: Accept queue on port $PORT is not saturated (Recv-Q=$RECV_Q < Send-Q=$SEND_Q)" >&2
  exit 1
fi

mkdir -p "$BASE/reports"
cat << EOF > "$BASE/reports/queue-triage.env"
SERVICE_PORT=$PORT
CONFIGURED_BACKLOG=$BACKLOG
OBSERVED_SEND_Q=$SEND_Q
OBSERVED_RECV_Q=$RECV_Q
QUEUE_TYPE=ACCEPT_QUEUE
EOF
