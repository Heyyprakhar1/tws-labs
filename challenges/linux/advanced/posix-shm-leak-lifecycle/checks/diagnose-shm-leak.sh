#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
REPORT_FILE="$BASE_DIR/reports/shm-triage.env"
UID_VAL=$(id -u)

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Triage report $REPORT_FILE does not exist"
  exit 1
fi

SEG=$(grep "^LEAKED_SEGMENT=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
BYTES=$(grep "^SEGMENT_BYTES=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
REASON=$(grep "^ORPHAN_REASON=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
IPC=$(grep "^IPC_INTERFACE=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

# Allow with or without /dev/shm/ prefix
SEG_BASE=$(basename "$SEG")
EXPECTED_BASE="tws_${UID_VAL}_telemetry"
EXPECTED_BASE_INST="tws_${TWS_INSTANCE_ID:-}_${TWS_SESSION_ID:-}_telemetry"
EXPECTED_BASE_SESS="tws_${TWS_SESSION_ID:-}_telemetry"

if [ "$SEG_BASE" != "$EXPECTED_BASE" ] && [ "$SEG_BASE" != "$EXPECTED_BASE_INST" ] && [ "$SEG_BASE" != "$EXPECTED_BASE_SESS" ]; then
  echo "FAIL: LEAKED_SEGMENT ('$SEG_BASE') must match expected orphaned object '$EXPECTED_BASE'"
  exit 1
fi

if [ "$BYTES" != "1048576" ]; then
  echo "FAIL: SEGMENT_BYTES ('$BYTES') must be exactly 1048576 (1 MB)"
  exit 1
fi

if [ "$REASON" != "UNHANDLED_SIGKILL" ]; then
  echo "FAIL: ORPHAN_REASON ('$REASON') must be UNHANDLED_SIGKILL"
  exit 1
fi

if [ "$IPC" != "POSIX_SHM" ]; then
  echo "FAIL: IPC_INTERFACE ('$IPC') must be POSIX_SHM"
  exit 1
fi

echo "PASS: Orphaned POSIX shared memory segment diagnosed"
exit 0
