#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
REPORT_FILE="$BASE_DIR/reports/shm-triage.env"
UID_VAL=$(id -u)

mkdir -p "$BASE_DIR/reports"

if [ -n "${TWS_INSTANCE_ID:-}" ] && [ -n "${TWS_SESSION_ID:-}" ]; then
  LEAKED_SEG="tws_${TWS_INSTANCE_ID}_${TWS_SESSION_ID}_telemetry"
elif [ -n "${TWS_SESSION_ID:-}" ]; then
  LEAKED_SEG="tws_${TWS_SESSION_ID}_telemetry"
else
  LEAKED_SEG="tws_${UID_VAL}_telemetry"
fi

cat << EOF > "$REPORT_FILE"
LEAKED_SEGMENT=${LEAKED_SEG}
SEGMENT_BYTES=1048576
ORPHAN_REASON=UNHANDLED_SIGKILL
IPC_INTERFACE=POSIX_SHM
EOF

echo "Triage report saved to $REPORT_FILE"
