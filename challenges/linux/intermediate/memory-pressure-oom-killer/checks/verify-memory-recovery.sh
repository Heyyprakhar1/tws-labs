. "$LAB_LIB"

SUPERVISOR_PID_FILE="mem-incident/var/run/supervisor.pid"
[ -f "$SUPERVISOR_PID_FILE" ] || fail "Supervisor PID file mem-incident/var/run/supervisor.pid missing."
SPID=$(cat "$SUPERVISOR_PID_FILE" | tr -d '[:space:]')
[ -n "$SPID" ] && [ -d "/proc/$SPID" ] || fail "Supervisor process is not running. Run ./mem-incident/bin/systemctl restart data-aggregator."

WORKER_PID_FILE="mem-incident/var/run/worker.pid"
[ -f "$WORKER_PID_FILE" ] || fail "Worker PID file mem-incident/var/run/worker.pid missing."
WPID=$(cat "$WORKER_PID_FILE" | tr -d '[:space:]')
[ -n "$WPID" ] && [ -d "/proc/$WPID" ] || fail "Worker process is not running. Run ./mem-incident/bin/systemctl restart data-aggregator."

WORKER_ADJ=$(cat "/proc/$WPID/oom_score_adj" 2>/dev/null || echo "0")
[ "$WORKER_ADJ" = "500" ] || fail "Worker oom_score_adj is $WORKER_ADJ (expected 500). Restart service with remediated configuration."

MARKER="mem-incident/reports/.memory-verified"
[ -f "$MARKER" ] || fail "Run ./mem-incident/bin/verify-memory to execute the load test and verify memory containment."

# Strict line-by-line schema validation
TIMESTAMP=""
TOTAL_BATCHES=""
MAX_CONCURRENCY=""
PEAK_RSS_KB=""
EXIT_CODE=""
STATUS=""
CHECKSUM=""
SEEN_KEYS=""
LINE_COUNT=0

while IFS='=' read -r key val || [ -n "$key" ]; do
  [ -z "$key" ] && continue
  LINE_COUNT=$((LINE_COUNT + 1))
  
  case " $SEEN_KEYS " in
    *" $key "*) fail "Duplicate key '$key' detected in .memory-verified." ;;
  esac
  SEEN_KEYS="$SEEN_KEYS $key"

  case "$key" in
    TIMESTAMP) TIMESTAMP="$val" ;;
    TOTAL_BATCHES) TOTAL_BATCHES="$val" ;;
    MAX_CONCURRENCY) MAX_CONCURRENCY="$val" ;;
    PEAK_RSS_KB) PEAK_RSS_KB="$val" ;;
    EXIT_CODE) EXIT_CODE="$val" ;;
    STATUS) STATUS="$val" ;;
    CHECKSUM) CHECKSUM="$val" ;;
    *) fail "Unknown field '$key' in .memory-verified." ;;
  esac
done < "$MARKER"

[ "$LINE_COUNT" -eq 7 ] || fail ".memory-verified must contain exactly 7 fields (got $LINE_COUNT)."
[ -n "$TIMESTAMP" ] || fail "TIMESTAMP missing in .memory-verified."
[ "$TOTAL_BATCHES" = "50" ] || fail "TOTAL_BATCHES must be 50 (got '$TOTAL_BATCHES')."
[ "$MAX_CONCURRENCY" -le 2 ] 2>/dev/null || fail "MAX_CONCURRENCY must be <= 2 (got '$MAX_CONCURRENCY')."
[ "$EXIT_CODE" = "0" ] || fail "EXIT_CODE must be 0 (got '$EXIT_CODE')."
[ "$STATUS" = "PASSED" ] || fail "STATUS must be PASSED (got '$STATUS')."

# Recompute SHA-256 digest over canonical payload
CANONICAL_PAYLOAD="$TIMESTAMP:$TOTAL_BATCHES:$MAX_CONCURRENCY:$PEAK_RSS_KB:$EXIT_CODE:$STATUS"
EXPECTED_CHECKSUM=$(printf "%s" "$CANONICAL_PAYLOAD" | sha256sum | awk '{print $1}')
[ "$CHECKSUM" = "$EXPECTED_CHECKSUM" ] || fail "Integrity check failed: CHECKSUM does not match canonical payload."

# Memory bounds assertion: 40 MB <= peak <= 90 MB (92,160 kB)
[ "$PEAK_RSS_KB" -ge 40000 ] 2>/dev/null || fail "PEAK_RSS_KB ($PEAK_RSS_KB) is unrealistically low."
[ "$PEAK_RSS_KB" -le 92160 ] 2>/dev/null || fail "PEAK_RSS_KB ($PEAK_RSS_KB) exceeds 92,160 kB (90 MB threshold)."

# Ensure worker PID was active at or before verification
WORKER_START=$(stat -c %Y "$WORKER_PID_FILE" 2>/dev/null || stat -f %m "$WORKER_PID_FILE")
MARKER_TIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER")
[ "$WORKER_START" -le "$MARKER_TIME" ] || fail "Worker was restarted after verification. Re-run ./mem-incident/bin/verify-memory."
