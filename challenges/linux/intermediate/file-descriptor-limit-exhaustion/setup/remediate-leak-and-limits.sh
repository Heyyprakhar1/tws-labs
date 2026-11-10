BASE="$HOME/fd-incident"
PID=$(cat "$BASE/var/run/event-collector.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$PID" ] || [ ! -d "/proc/$PID" ]; then
  "$BASE/bin/systemctl" restart event-collector
  PID=$(cat "$BASE/var/run/event-collector.pid" | tr -d '[:space:]')
fi
SOFT=$(awk '/^Max open files/ { print $4 }' "/proc/$PID/limits")
HARD=$(awk '/^Max open files/ { print $5 }' "/proc/$PID/limits")
FDS=$(ls -1 "/proc/$PID/fd" | wc -l)

cat << EOF > "$BASE/reports/fd-triage.env"
WORKER_PID=$PID
NOFILE_SOFT=$SOFT
NOFILE_HARD=$HARD
OPEN_FD_COUNT=$FDS
ERROR_CODE=EMFILE
FAILING_SYSCALL=open
EOF

cat << 'EOF' > "$BASE/reports/leak-investigation.env"
LEAK_FD_TYPE=file
LEAK_TARGET_PATTERN=chunk-*.tmp (deleted)
LEAK_CONFIG_FILE=config/worker.env
LEAK_CONFIG_KEY=AUTO_CLOSE_CHUNKS
ROOT_CAUSE=unclosed temporary chunk file descriptors
EOF

rm -f "$BASE/.fd-audit.passed"
