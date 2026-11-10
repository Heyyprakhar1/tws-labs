#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
REPORT_FILE="$BASE_DIR/reports/inversion-analysis.env"
TRACE_FILE="$BASE_DIR/traces/deadlock-strace.log"

if [ ! -f "$TRACE_FILE" ]; then
  echo "FAIL: Reference syscall trace $TRACE_FILE missing"
  exit 1
fi

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Analysis report $REPORT_FILE does not exist"
  exit 1
fi

INVERSION_TYPE=$(grep "^INVERSION_TYPE=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
T1_HOLDS=$(grep "^THREAD_1_HOLDS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
T1_WAITS=$(grep "^THREAD_1_WAITS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
T2_HOLDS=$(grep "^THREAD_2_HOLDS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
T2_WAITS=$(grep "^THREAD_2_WAITS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
RESOLUTION=$(grep "^RESOLUTION_STRATEGY=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$INVERSION_TYPE" != "AB_BA_LOCK_INVERSION" ]; then
  echo "FAIL: INVERSION_TYPE must be AB_BA_LOCK_INVERSION (got '$INVERSION_TYPE')"
  exit 1
fi

if [ "$T1_HOLDS" != "MUTEX_A" ] || [ "$T1_WAITS" != "MUTEX_B" ]; then
  echo "FAIL: Thread 1 must hold MUTEX_A and wait on MUTEX_B"
  exit 1
fi

if [ "$T2_HOLDS" != "MUTEX_B" ] || [ "$T2_WAITS" != "MUTEX_A" ]; then
  echo "FAIL: Thread 2 must hold MUTEX_B and wait on MUTEX_A"
  exit 1
fi

if [ "$RESOLUTION" != "ORDERED_RESOURCE_ACQUISITION" ]; then
  echo "FAIL: RESOLUTION_STRATEGY must be ORDERED_RESOURCE_ACQUISITION (got '$RESOLUTION')"
  exit 1
fi

echo "PASS: Lock inversion analysis validated"
exit 0
