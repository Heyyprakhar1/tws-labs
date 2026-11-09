#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
REPORT_FILE="$BASE_DIR/reports/lifecycle-analysis.env"

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Lifecycle analysis report $REPORT_FILE does not exist"
  exit 1
fi

UNLINK_NAME=$(grep "^UNLINK_REMOVES_NAME=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
UNLINK_MAP=$(grep "^UNLINK_FREES_MAPPING_IMMEDIATELY=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
MAPS_STATUS=$(grep "^KERNEL_MAPS_STATUS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
RECLAIM=$(grep "^RECLAMATION_CONDITION=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$UNLINK_NAME" != "true" ]; then
  echo "FAIL: UNLINK_REMOVES_NAME must be true (shm_unlink removes the entry from /dev/shm)"
  exit 1
fi

if [ "$UNLINK_MAP" != "false" ]; then
  echo "FAIL: UNLINK_FREES_MAPPING_IMMEDIATELY must be false (active memory mappings remain valid)"
  exit 1
fi

if [ "$MAPS_STATUS" != "DELETED" ] && [ "$MAPS_STATUS" != "(deleted)" ]; then
  echo "FAIL: KERNEL_MAPS_STATUS must be DELETED"
  exit 1
fi

if [ "$RECLAIM" != "LAST_REFERENCE_CLOSED" ]; then
  echo "FAIL: RECLAMATION_CONDITION must be LAST_REFERENCE_CLOSED"
  exit 1
fi

echo "PASS: POSIX shared memory unlinking vs mapping lifecycle analyzed"
exit 0
