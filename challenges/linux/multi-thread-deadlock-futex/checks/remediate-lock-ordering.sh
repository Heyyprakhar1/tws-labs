#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
CONF_FILE="$BASE_DIR/config/service.env"
PID_FILE="$BASE_DIR/var/service.pid"

if [ ! -f "$CONF_FILE" ]; then
  echo "FAIL: Configuration file $CONF_FILE does not exist"
  exit 1
fi

ORDER_VAL=$(grep "^ORDER_LOCKS_BY_ID=" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')
if [ "$ORDER_VAL" != "true" ]; then
  echo "FAIL: ORDER_LOCKS_BY_ID must be set to true in $CONF_FILE"
  exit 1
fi

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "FAIL: order-processor is not running after restart"
  exit 1
fi

PID=$(cat "$PID_FILE")
sleep 0.2
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: order-processor crashed or failed to run"
  exit 1
fi

echo "PASS: Deterministic lock ordering enabled and service running"
exit 0
