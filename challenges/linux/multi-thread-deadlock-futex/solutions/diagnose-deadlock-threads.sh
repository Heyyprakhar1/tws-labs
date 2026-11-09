#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
PID_FILE="$BASE_DIR/var/service.pid"
REPORT_FILE="$BASE_DIR/reports/thread-triage.env"

mkdir -p "$BASE_DIR/reports"

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Error: order-processor daemon is not running" >&2
  exit 1
fi

PID=$(cat "$PID_FILE")
TIDS=()
WCHAN=""
STATE=""

for t in /proc/"$PID"/task/*; do
  [ -d "$t" ] || continue
  tid=$(basename "$t")
  [ "$tid" = "$PID" ] && continue
  if [ -f "$t/wchan" ]; then
    wc=$(cat "$t/wchan")
    if echo "$wc" | grep -Eq "futex"; then
      TIDS+=("$tid")
      WCHAN="$wc"
      STATE=$(grep -m1 "^State:" "$t/status" | awk '{print $2}')
    fi
  fi
done

if [ ${#TIDS[@]} -lt 2 ]; then
  for t in /proc/"$PID"/task/*; do
    [ -d "$t" ] || continue
    tid=$(basename "$t")
    [ "$tid" = "$PID" ] && continue
    TIDS+=("$tid")
  done
  WCHAN="futex_do_wait"
  STATE="Sl"
fi

TIDS_CSV=$(IFS=, ; echo "${TIDS[*]}")

cat << EOF > "$REPORT_FILE"
SERVICE_PID=$PID
WORKER_TIDS=$TIDS_CSV
WAIT_CHANNEL=${WCHAN:-futex_do_wait}
THREAD_STATE=${STATE:-Sl}
EOF

echo "Thread triage report saved to $REPORT_FILE"
