#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
mkdir -p "$INCIDENT_DIR/reports"

cat > "$INCIDENT_DIR/reports/lifecycle-analysis.env" <<'EOF'
REQUIRED_SIGNAL=SIGCHLD
REAP_SYSCALL=waitpid
WAITPID_FLAGS=WNOHANG
LOOP_STRATEGY=WHILE_POSITIVE_PID
EOF
