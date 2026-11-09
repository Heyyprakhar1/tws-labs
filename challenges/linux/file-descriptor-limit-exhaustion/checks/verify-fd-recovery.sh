. "$LAB_LIB"

PID_FILE="fd-incident/var/run/event-collector.pid"
[ -f "$PID_FILE" ] || fail "Service PID file fd-incident/var/run/event-collector.pid missing."
PID=$(cat "$PID_FILE" | tr -d '[:space:]')
[ -n "$PID" ] || fail "Service PID file is empty."
[ -d "/proc/$PID" ] || fail "Service process $PID is not running. Run ./fd-incident/bin/systemctl restart event-collector."

LIMITS_FILE="/proc/$PID/limits"
[ -f "$LIMITS_FILE" ] || fail "Cannot inspect /proc/$PID/limits."
SOFT=$(awk '/^Max open files/ { print $4 }' "$LIMITS_FILE")
HARD=$(awk '/^Max open files/ { print $5 }' "$LIMITS_FILE")
[ "$SOFT" -ge 4096 ] 2>/dev/null || fail "Running service Soft Limit is $SOFT (expected >= 4096). Restart service with updated unit."
[ "$HARD" -ge 4096 ] 2>/dev/null || fail "Running service Hard Limit is $HARD (expected >= 4096). Restart service with updated unit."

AUDIT_MARKER="fd-incident/.fd-audit.passed"
[ -f "$AUDIT_MARKER" ] || fail "Run ./fd-incident/bin/verify-fds to verify recovery and test under load."

DELETED_CHUNKS=$(ls -l "/proc/$PID/fd" 2>/dev/null | grep -E 'chunk-.*\.tmp.*\(deleted\)' | wc -l || true)
[ "$DELETED_CHUNKS" -eq 0 ] || fail "Process $PID still has $DELETED_CHUNKS open deleted chunk descriptors. Fix AUTO_CLOSE_CHUNKS and restart service."
