#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
CONF_FILE="$BASE_DIR/config/telemetry.env"
PID_FILE="$BASE_DIR/var/telemetry.pid"
UID_VAL=$(id -u)
SHM_FILE="/dev/shm/tws_${UID_VAL}_telemetry"
if [ -n "${TWS_INSTANCE_ID:-}" ] && [ -n "${TWS_SESSION_ID:-}" ] && [ -e "/dev/shm/tws_${TWS_INSTANCE_ID}_${TWS_SESSION_ID}_telemetry" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_INSTANCE_ID}_${TWS_SESSION_ID}_telemetry"
elif [ -n "${TWS_SESSION_ID:-}" ] && [ -e "/dev/shm/tws_${TWS_SESSION_ID}_telemetry" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_SESSION_ID}_telemetry"
fi

if [ ! -f "$CONF_FILE" ]; then
  echo "FAIL: Configuration file $CONF_FILE does not exist"
  exit 1
fi

AUTO_UNLINK=$(grep "^AUTO_UNLINK_ON_SHUTDOWN=" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')
DEFENSIVE=$(grep "^DEFENSIVE_STARTUP_CLEANUP=" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$AUTO_UNLINK" != "true" ]; then
  echo "FAIL: AUTO_UNLINK_ON_SHUTDOWN must be true in $CONF_FILE"
  exit 1
fi

if [ "$DEFENSIVE" != "true" ]; then
  echo "FAIL: DEFENSIVE_STARTUP_CLEANUP must be true in $CONF_FILE"
  exit 1
fi

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "FAIL: telemetry-collector is not currently running. Start it with ./bin/telemetry-ctl start"
  exit 1
fi

PID=$(cat "$PID_FILE")

# Verify the shared memory segment exists and is owned by UID
if [ ! -e "$SHM_FILE" ]; then
  echo "FAIL: Expected shared memory object $SHM_FILE was not created by running service"
  exit 1
fi

OWNER=$(stat -c '%u' "$SHM_FILE" 2>/dev/null || echo "")
if [ "$OWNER" != "$UID_VAL" ]; then
  echo "FAIL: $SHM_FILE ownership mismatch: expected UID $UID_VAL, got $OWNER"
  exit 1
fi

echo "PASS: Shared memory leak remediated, defensive lifecycle configured, and service running"
exit 0
