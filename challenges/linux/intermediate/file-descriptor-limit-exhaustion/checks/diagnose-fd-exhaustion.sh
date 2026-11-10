. "$LAB_LIB"

REPORT="fd-incident/reports/fd-triage.env"
[ -f "$REPORT" ] || fail "Report fd-incident/reports/fd-triage.env does not exist."

INITIAL_PID_FILE="fd-incident/var/run/.initial-worker.pid"
PID_FILE="fd-incident/var/run/event-collector.pid"
if [ -f "$INITIAL_PID_FILE" ]; then
  EXPECTED_PID=$(cat "$INITIAL_PID_FILE" | tr -d '[:space:]')
elif [ -f "$PID_FILE" ]; then
  EXPECTED_PID=$(cat "$PID_FILE" | tr -d '[:space:]')
else
  fail "Service PID file fd-incident/var/run/event-collector.pid missing."
fi

[ -n "$EXPECTED_PID" ] || fail "PID file is empty."

REPORTED_PID=$(grep -E '^[[:space:]]*WORKER_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_SOFT=$(grep -E '^[[:space:]]*NOFILE_SOFT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_HARD=$(grep -E '^[[:space:]]*NOFILE_HARD=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_FDS=$(grep -E '^[[:space:]]*OPEN_FD_COUNT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_ERR=$(grep -E '^[[:space:]]*ERROR_CODE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_SYS=$(grep -E '^[[:space:]]*FAILING_SYSCALL=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$REPORTED_PID" ] || fail "WORKER_PID is missing from fd-triage.env."
[ "$REPORTED_PID" = "$EXPECTED_PID" ] || fail "WORKER_PID ($REPORTED_PID) does not match active service PID ($EXPECTED_PID)."

[ "$REPORTED_SOFT" = "256" ] || fail "NOFILE_SOFT must be 256 (got '$REPORTED_SOFT')."
[ "$REPORTED_HARD" = "256" ] || fail "NOFILE_HARD must be 256 (got '$REPORTED_HARD')."
[ "$REPORTED_FDS" -ge 255 ] && [ "$REPORTED_FDS" -le 256 ] 2>/dev/null || fail "OPEN_FD_COUNT must be 256 (got '$REPORTED_FDS')."
[ "$REPORTED_ERR" = "EMFILE" ] || fail "ERROR_CODE must be EMFILE (got '$REPORTED_ERR')."
[ "$REPORTED_SYS" = "open" ] || fail "FAILING_SYSCALL must be open (got '$REPORTED_SYS')."
