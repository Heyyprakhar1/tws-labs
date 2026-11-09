. "$LAB_LIB"

REPORT="mem-incident/reports/memory-triage.env"
[ -f "$REPORT" ] || fail "Report mem-incident/reports/memory-triage.env does not exist."

INITIAL_WORKER_PID_FILE="mem-incident/var/run/.initial-worker.pid"
WORKER_PID_FILE="mem-incident/var/run/worker.pid"
INITIAL_WPID=""
CURRENT_WPID=""
if [ -f "$INITIAL_WORKER_PID_FILE" ]; then
  INITIAL_WPID=$(cat "$INITIAL_WORKER_PID_FILE" | tr -d '[:space:]')
fi
if [ -f "$WORKER_PID_FILE" ]; then
  CURRENT_WPID=$(cat "$WORKER_PID_FILE" | tr -d '[:space:]')
fi
[ -n "$INITIAL_WPID" ] || [ -n "$CURRENT_WPID" ] || fail "Worker PID file mem-incident/var/run/worker.pid missing."

INITIAL_SUPERVISOR_PID_FILE="mem-incident/var/run/.initial-supervisor.pid"
SUPERVISOR_PID_FILE="mem-incident/var/run/supervisor.pid"
INITIAL_SPID=""
CURRENT_SPID=""
if [ -f "$INITIAL_SUPERVISOR_PID_FILE" ]; then
  INITIAL_SPID=$(cat "$INITIAL_SUPERVISOR_PID_FILE" | tr -d '[:space:]')
fi
if [ -f "$SUPERVISOR_PID_FILE" ]; then
  CURRENT_SPID=$(cat "$SUPERVISOR_PID_FILE" | tr -d '[:space:]')
fi
[ -n "$INITIAL_SPID" ] || [ -n "$CURRENT_SPID" ] || fail "Supervisor PID file mem-incident/var/run/supervisor.pid missing."

REPORTED_WPID=$(grep -E '^[[:space:]]*WORKER_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_SPID=$(grep -E '^[[:space:]]*SUPERVISOR_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_MEM_TOTAL=$(grep -E '^[[:space:]]*MEM_TOTAL_KB=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_MEM_AVAIL=$(grep -E '^[[:space:]]*MEM_AVAILABLE_KB=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_VM_RSS=$(grep -E '^[[:space:]]*WORKER_VM_RSS_KB=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_EXIT_CODE=$(grep -E '^[[:space:]]*LAST_EXIT_CODE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_SIGNAL=$(grep -E '^[[:space:]]*TERMINATION_SIGNAL=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$REPORTED_WPID" ] || fail "WORKER_PID is missing from memory-triage.env."
[ "$REPORTED_WPID" = "${INITIAL_WPID:-}" ] || [ "$REPORTED_WPID" = "${CURRENT_WPID:-}" ] || fail "WORKER_PID ($REPORTED_WPID) does not match active worker PID (${CURRENT_WPID:-$INITIAL_WPID})."

[ -n "$REPORTED_SPID" ] || fail "SUPERVISOR_PID is missing from memory-triage.env."
[ "$REPORTED_SPID" = "${INITIAL_SPID:-}" ] || [ "$REPORTED_SPID" = "${CURRENT_SPID:-}" ] || fail "SUPERVISOR_PID ($REPORTED_SPID) does not match active supervisor PID (${CURRENT_SPID:-$INITIAL_SPID})."

ACTUAL_MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
[ -n "$REPORTED_MEM_TOTAL" ] || fail "MEM_TOTAL_KB is missing from memory-triage.env."
[ "$REPORTED_MEM_TOTAL" = "$ACTUAL_MEM_TOTAL" ] || fail "MEM_TOTAL_KB ($REPORTED_MEM_TOTAL) does not match /proc/meminfo ($ACTUAL_MEM_TOTAL)."

ACTUAL_MEM_AVAIL=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
[ -n "$REPORTED_MEM_AVAIL" ] || fail "MEM_AVAILABLE_KB is missing from memory-triage.env."
DIFF_AVAIL=$(( ACTUAL_MEM_AVAIL > REPORTED_MEM_AVAIL ? ACTUAL_MEM_AVAIL - REPORTED_MEM_AVAIL : REPORTED_MEM_AVAIL - ACTUAL_MEM_AVAIL ))
MAX_DIFF_AVAIL=$(( ACTUAL_MEM_AVAIL / 10 ))
[ "$DIFF_AVAIL" -le "$MAX_DIFF_AVAIL" ] || fail "MEM_AVAILABLE_KB ($REPORTED_MEM_AVAIL) diverges significantly from /proc/meminfo ($ACTUAL_MEM_AVAIL)."

[ -n "$REPORTED_VM_RSS" ] || fail "WORKER_VM_RSS_KB is missing from memory-triage.env."
if [ -f "/proc/$REPORTED_WPID/status" ]; then
  ACTUAL_VM_RSS=$(awk '/^VmRSS:/ {print $2}' "/proc/$REPORTED_WPID/status")
  DIFF_RSS=$(( ACTUAL_VM_RSS > REPORTED_VM_RSS ? ACTUAL_VM_RSS - REPORTED_VM_RSS : REPORTED_VM_RSS - ACTUAL_VM_RSS ))
  MAX_DIFF_RSS=$(( ACTUAL_VM_RSS / 5 ))
  [ "$DIFF_RSS" -le "$MAX_DIFF_RSS" ] || fail "WORKER_VM_RSS_KB ($REPORTED_VM_RSS) diverges from active process VmRSS ($ACTUAL_VM_RSS)."
fi

[ "$REPORTED_EXIT_CODE" = "137" ] || fail "LAST_EXIT_CODE must be 137 (got '$REPORTED_EXIT_CODE')."
[ "$REPORTED_SIGNAL" = "SIGKILL" ] || fail "TERMINATION_SIGNAL must be SIGKILL (got '$REPORTED_SIGNAL')."
