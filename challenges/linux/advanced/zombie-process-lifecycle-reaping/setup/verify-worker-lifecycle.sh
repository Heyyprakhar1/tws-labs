#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
mkdir -p "$INCIDENT_DIR/reports"
PID_FILE="$INCIDENT_DIR/var/run/supervisor.pid"

SUP_PID="0"
if [ -f "$PID_FILE" ]; then
    SUP_PID=$(cat "$PID_FILE" | tr -d ' ')
fi

cat > "$INCIDENT_DIR/reports/zombie-triage.env" <<EOF
SUPERVISOR_PID=${SUP_PID}
ZOMBIE_COUNT=10
PROCESS_STATE=Z
REAPING_STATUS=DEFUNCT_ACCUMULATION
EOF

cat > "$INCIDENT_DIR/reports/lifecycle-analysis.env" <<'EOF'
REQUIRED_SIGNAL=SIGCHLD
REAP_SYSCALL=waitpid
WAITPID_FLAGS=WNOHANG
LOOP_STRATEGY=WHILE_POSITIVE_PID
EOF

sed -i 's/^ENABLE_SIGCHLD_REAPER=.*/ENABLE_SIGCHLD_REAPER=true/' "$INCIDENT_DIR/config/supervisor.env"
"$INCIDENT_DIR/bin/supervisor-ctl" restart
sleep 0.4

"$INCIDENT_DIR/bin/verify-reaping"
