#!/bin/bash
set -euo pipefail

PID_FILE="$HOME/port-incident/var/run/rogue-listener.pid"
IDENTITY_FILE="$HOME/port-incident/var/run/.rogue-listener.identity"
if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  (exec node "$HOME/port-incident/bin/rogue-listener" </dev/null >> "$HOME/port-incident/logs/rogue-listener.log" 2>&1 &)
  for i in {1..20}; do
    if [ -f "$PID_FILE" ] && [ -f "$IDENTITY_FILE" ]; then break; fi
    sleep 0.1
  done
  chmod 0600 "$IDENTITY_FILE" 2>/dev/null || true
fi

PID=$(cat "$PID_FILE" | tr -d '[:space:]')
cat << EOF > "$HOME/port-incident/reports/socket-triage.env"
CONFLICT_PID=$PID
CONFLICT_PROCESS=rogue-listener
BIND_ADDRESS=0.0.0.0
EOF
