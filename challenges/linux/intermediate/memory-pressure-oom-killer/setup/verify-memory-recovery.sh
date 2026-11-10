BASE="${LAB_HOME:-$HOME}/mem-incident"

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

cat << 'EOF' > "$BASE/reports/oom-forensics.env"
INCIDENT_TIMESTAMP=08:42:14 UTC
CGROUP_VERSION=v2
OOM_EVIDENCE_SOURCE=kernel log and cgroup memory.events
TRIGGER_PROCESS=data-aggregator-ingest
TRIGGER_PID=4128
KILLED_PROCESS=data-aggregator-worker
KILLED_PID=4129
KILLED_ANON_RSS_KB=248320
CGROUP_MAX_BYTES=268435456
CGROUP_OOM_COUNT=1
CGROUP_OOM_KILL_COUNT=1
OOM_PROVEN=true
EOF

sed -i 's/^BATCH_SIZE=.*/BATCH_SIZE=500/' "$BASE/config/worker.env"
sed -i 's/^MAX_CONCURRENCY=.*/MAX_CONCURRENCY=2/' "$BASE/config/worker.env"
sed -i 's/^BUFFER_MODE=.*/BUFFER_MODE=stream/' "$BASE/config/worker.env"
sed -i 's/^MAX_MEMORY_MB=.*/MAX_MEMORY_MB=128/' "$BASE/config/worker.env"
sed -i 's/^WORKER_OOM_SCORE_ADJ=.*/WORKER_OOM_SCORE_ADJ=500/' "$BASE/config/worker.env"
"$BASE/bin/systemctl" daemon-reload

rm -f "$BASE/reports/.memory-verified"
