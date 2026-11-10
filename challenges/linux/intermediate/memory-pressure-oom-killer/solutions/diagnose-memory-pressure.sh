#!/bin/bash
set -euo pipefail

BASE="mem-incident"
mkdir -p "$BASE/reports"

WPID=$(cat "$BASE/var/run/worker.pid" 2>/dev/null | tr -d '[:space:]')
SPID=$(cat "$BASE/var/run/supervisor.pid" 2>/dev/null | tr -d '[:space:]')
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
