#!/bin/bash
set -euo pipefail

PID_FILE="$HOME/port-incident/var/run/rogue-listener.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" | tr -d '[:space:]')
  cat << EOF > "$HOME/port-incident/reports/socket-triage.env"
CONFLICT_PID=$PID
CONFLICT_PROCESS=rogue-listener
BIND_ADDRESS=0.0.0.0
EOF
fi

"$HOME/port-incident/bin/kill-listener" || true
sed -i 's/METRICS_BIND=.*/METRICS_BIND=0.0.0.0/' "$HOME/port-incident/config/proxy.env"

cd "$HOME/port-incident"
./bin/auth-proxy --start

rm -f "$HOME/port-incident/.socket-audit.passed"
