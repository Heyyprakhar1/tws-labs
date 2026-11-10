BASE="$HOME/fd-incident"
rm -f "$BASE/reports/fd-triage.env" "$BASE/reports/leak-investigation.env" "$BASE/.fd-audit.passed"
PID=$(cat "$BASE/var/run/event-collector.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$PID" ] || [ ! -d "/proc/$PID" ]; then
  "$BASE/bin/systemctl" restart event-collector
fi
