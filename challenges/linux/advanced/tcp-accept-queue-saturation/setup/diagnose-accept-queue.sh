BASE="$HOME/tcp-incident"
rm -f "$BASE/reports/queue-triage.env" "$BASE/reports/metric-drops.env" "$BASE/reports/verification.marker"
PID=$(cat "$BASE/var/run/api-server.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  "$BASE/bin/api-ctl" restart
fi
