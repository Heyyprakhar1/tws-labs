#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
REPORT_FILE="$BASE_DIR/reports/recovery-report.env"
PID_FILE="$BASE_DIR/var/service.pid"

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "FAIL: order-processor is not running"
  exit 1
fi

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Verification report $REPORT_FILE does not exist. Run ./bin/benchmark-concurrency"
  exit 1
fi

STATUS=$(grep "^BENCHMARK_STATUS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
COMPLETED=$(grep "^TRANSFERS_COMPLETED=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
DEADLOCKS=$(grep "^DEADLOCKS_DETECTED=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
ORDERING=$(grep "^LOCK_ORDERING=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$STATUS" != "SUCCESS" ]; then
  echo "FAIL: BENCHMARK_STATUS must be SUCCESS (got '$STATUS')"
  exit 1
fi

if [ "$COMPLETED" != "50" ]; then
  echo "FAIL: TRANSFERS_COMPLETED must be 50 (got '$COMPLETED')"
  exit 1
fi

if [ "$DEADLOCKS" != "0" ]; then
  echo "FAIL: DEADLOCKS_DETECTED must be 0 (got '$DEADLOCKS')"
  exit 1
fi

if [ "$ORDERING" != "DETERMINISTIC" ]; then
  echo "FAIL: LOCK_ORDERING must be DETERMINISTIC (got '$ORDERING')"
  exit 1
fi

echo "PASS: Concurrent throughput and zero-deadlock execution verified"
exit 0
