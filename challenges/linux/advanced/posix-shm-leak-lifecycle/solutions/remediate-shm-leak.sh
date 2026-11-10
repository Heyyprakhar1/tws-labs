#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
CONF_FILE="$BASE_DIR/config/telemetry.env"

# Reclaim stale segment first
"$BASE_DIR/bin/telemetry-ctl" cleanup || true

# Update configuration
sed -i 's/^AUTO_UNLINK_ON_SHUTDOWN=.*/AUTO_UNLINK_ON_SHUTDOWN=true/' "$CONF_FILE"
sed -i 's/^DEFENSIVE_STARTUP_CLEANUP=.*/DEFENSIVE_STARTUP_CLEANUP=true/' "$CONF_FILE"

# Start the service
"$BASE_DIR/bin/telemetry-ctl" restart
