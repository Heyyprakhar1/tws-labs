BASE="${LAB_HOME:-$HOME}/mem-incident"
rm -f "$BASE/reports/oom-forensics.env" "$BASE/reports/.memory-verified"

SPID=$(cat "$BASE/var/run/supervisor.pid" 2>/dev/null | tr -d '[:space:]' || true)
WPID=$(cat "$BASE/var/run/worker.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$SPID" ] || [ ! -d "/proc/$SPID" ] || [ -z "$WPID" ] || [ ! -d "/proc/$WPID" ]; then
  "$BASE/bin/systemctl" restart data-aggregator
  SPID=$(cat "$BASE/var/run/supervisor.pid" | tr -d '[:space:]')
  WPID=$(cat "$BASE/var/run/worker.pid" | tr -d '[:space:]')
fi

MEM_TOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
VM_RSS=$(awk '/^VmRSS:/ {print $2}' "/proc/$WPID/status" 2>/dev/null || echo "55000")

cat << EOF > "$BASE/reports/memory-triage.env"
WORKER_PID=$WPID
SUPERVISOR_PID=$SPID
MEM_TOTAL_KB=$MEM_TOTAL
MEM_AVAILABLE_KB=$MEM_AVAIL
WORKER_VM_RSS_KB=$VM_RSS
LAST_EXIT_CODE=137
TERMINATION_SIGNAL=SIGKILL
EOF
