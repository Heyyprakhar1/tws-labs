BASE="${LAB_HOME:-$HOME}/mem-incident"
rm -f "$BASE/reports/memory-triage.env" "$BASE/reports/oom-forensics.env" "$BASE/reports/.memory-verified"

SPID=$(cat "$BASE/var/run/supervisor.pid" 2>/dev/null | tr -d '[:space:]' || true)
WPID=$(cat "$BASE/var/run/worker.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$SPID" ] || [ ! -d "/proc/$SPID" ] || [ -z "$WPID" ] || [ ! -d "/proc/$WPID" ]; then
  "$BASE/bin/systemctl" restart data-aggregator
fi
