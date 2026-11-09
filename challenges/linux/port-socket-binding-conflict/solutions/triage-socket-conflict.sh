PID=$(cat "$HOME/port-incident/var/run/rogue-listener.pid")
cat << EOF > "$HOME/port-incident/reports/socket-triage.env"
CONFLICT_PID=$PID
CONFLICT_PROCESS=rogue-listener
BIND_ADDRESS=0.0.0.0
EOF
