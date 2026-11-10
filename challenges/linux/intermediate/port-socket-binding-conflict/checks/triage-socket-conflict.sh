. "$LAB_LIB"

REPORT="port-incident/reports/socket-triage.env"
[ -f "$REPORT" ] || fail "Report port-incident/reports/socket-triage.env does not exist."

# Read expected values from environment / pid file
PID_FILE="port-incident/var/run/rogue-listener.pid"
REF_FILE="port-incident/var/run/.rogue-listener.ref"
if [ -f "$PID_FILE" ]; then
  EXPECTED_PID=$(cat "$PID_FILE" | tr -d '[:space:]')
elif [ -f "$REF_FILE" ]; then
  EXPECTED_PID=$(cat "$REF_FILE" | tr -d '[:space:]')
else
  fail "Service PID file port-incident/var/run/rogue-listener.pid missing."
fi

REPORTED_PID=$(grep -E '^[[:space:]]*CONFLICT_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_PROC=$(grep -E '^[[:space:]]*CONFLICT_PROCESS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
REPORTED_BIND=$(grep -E '^[[:space:]]*BIND_ADDRESS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$REPORTED_PID" ] || fail "CONFLICT_PID is not defined in socket-triage.env."
[ "$REPORTED_PID" = "$EXPECTED_PID" ] || fail "CONFLICT_PID ($REPORTED_PID) does not match actual conflicting listener PID ($EXPECTED_PID)."

# Independent process validation: never trust learner input without verifying PID in /proc
if [ -d "/proc/$REPORTED_PID" ]; then
  PROC_UID=$(stat -c %u "/proc/$REPORTED_PID" 2>/dev/null || true)
  [ "$PROC_UID" = "$UID" ] || fail "Reported PID $REPORTED_PID is not owned by current session user ($UID)."
  CMDLINE=$(cat "/proc/$REPORTED_PID/cmdline" 2>/dev/null | tr '\0' ' ' || true)
  echo "$CMDLINE" | grep -q "rogue-listener" || fail "Process $REPORTED_PID is not rogue-listener."
fi

[ "$REPORTED_PROC" = "rogue-listener" ] || fail "CONFLICT_PROCESS must be rogue-listener."
[ "$REPORTED_BIND" = "0.0.0.0" ] || fail "BIND_ADDRESS must be 0.0.0.0."
