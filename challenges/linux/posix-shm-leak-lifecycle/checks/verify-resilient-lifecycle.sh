#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
REPORT_FILE="$BASE_DIR/reports/recovery-report.env"
UID_VAL=$(id -u)

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Verification report $REPORT_FILE does not exist. Run ./bin/verify-shm-resilience"
  exit 1
fi

STATUS=$(grep "^VERIFICATION_STATUS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
LEAKS=$(grep "^LEAKS_DETECTED=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
STRATEGY=$(grep "^CLEANUP_STRATEGY=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
MAX_BYTES=$(grep "^MAX_ALLOCATION_BYTES=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$STATUS" != "SUCCESS" ]; then
  echo "FAIL: VERIFICATION_STATUS ('$STATUS') must be SUCCESS"
  exit 1
fi

if [ "$LEAKS" != "0" ]; then
  echo "FAIL: LEAKS_DETECTED ('$LEAKS') must be 0"
  exit 1
fi

if [ "$STRATEGY" != "DEFENSIVE_STARTUP_AND_SIGTERM_UNLINK" ]; then
  echo "FAIL: CLEANUP_STRATEGY ('$STRATEGY') must be DEFENSIVE_STARTUP_AND_SIGTERM_UNLINK"
  exit 1
fi

if [ "$MAX_BYTES" != "1052672" ]; then
  echo "FAIL: MAX_ALLOCATION_BYTES ('$MAX_BYTES') must be 1052672"
  exit 1
fi

echo "PASS: Resilient POSIX shared memory lifecycle verified"
exit 0
