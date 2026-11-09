BASE="$HOME/spool-incident"
rm -f "$BASE/reports/spool-triage.env" "$BASE/reports/arg-limits.env" "$BASE/reports/verification.marker"
PID=$(cat "$BASE/var/run/spooler.pid" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  "$BASE/bin/spool-ctl" restart
fi
