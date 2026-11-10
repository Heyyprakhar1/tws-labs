. "$LAB_LIB"

REPORT="tcp-incident/reports/queue-triage.env"
[ -f "$REPORT" ] || fail "Report tcp-incident/reports/queue-triage.env does not exist."

CONFIG="tcp-incident/config/api.env"
[ -f "$CONFIG" ] || fail "Configuration tcp-incident/config/api.env missing."
EXPECTED_PORT=$(grep -E '^[[:space:]]*PORT=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

REPORTED_PORT=$(grep -E '^[[:space:]]*SERVICE_PORT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_BACKLOG=$(grep -E '^[[:space:]]*CONFIGURED_BACKLOG=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_SEND_Q=$(grep -E '^[[:space:]]*OBSERVED_SEND_Q=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_RECV_Q=$(grep -E '^[[:space:]]*OBSERVED_RECV_Q=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_TYPE=$(grep -E '^[[:space:]]*QUEUE_TYPE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$REPORTED_PORT" ] || fail "SERVICE_PORT is missing from queue-triage.env."
[ "$REPORTED_PORT" = "$EXPECTED_PORT" ] || fail "SERVICE_PORT ($REPORTED_PORT) does not match configured PORT ($EXPECTED_PORT)."
[ "$REPORTED_BACKLOG" = "5" ] || fail "CONFIGURED_BACKLOG must be 5 (got '$REPORTED_BACKLOG')."
[ "$REPORTED_SEND_Q" = "5" ] || fail "OBSERVED_SEND_Q must be 5 (got '$REPORTED_SEND_Q')."
[ "$REPORTED_RECV_Q" = "6" ] || [ "$REPORTED_RECV_Q" = "5" ] || fail "OBSERVED_RECV_Q must be 5 or 6 (got '$REPORTED_RECV_Q')."
[ "$REPORTED_TYPE" = "ACCEPT_QUEUE" ] || fail "QUEUE_TYPE must be ACCEPT_QUEUE (got '$REPORTED_TYPE')."
