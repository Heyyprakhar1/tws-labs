#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
sed -i 's/^ENABLE_SIGCHLD_REAPER=.*/ENABLE_SIGCHLD_REAPER=true/' "$INCIDENT_DIR/config/supervisor.env"
"$INCIDENT_DIR/bin/supervisor-ctl" restart
sleep 0.4
