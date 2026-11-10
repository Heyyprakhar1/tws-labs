#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/deadlock-incident"
PID_FILE="$BASE_DIR/var/service.pid"
REPORT_FILE="$BASE_DIR/reports/thread-triage.env"

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "FAIL: order-processor daemon is not currently running"
  exit 1
fi

PID=$(cat "$PID_FILE")

if [ ! -d "/proc/$PID/task" ]; then
  echo "FAIL: Cannot inspect thread tasks for PID $PID"
  exit 1
fi

# Verify at least 2 worker threads in futex wait
FUTEX_THREADS=0
for t in /proc/"$PID"/task/*; do
  [ -d "$t" ] || continue
  TID=$(basename "$t")
  [ "$TID" = "$PID" ] && continue
  if [ -f "$t/wchan" ]; then
    WCHAN=$(cat "$t/wchan")
    if echo "$WCHAN" | grep -Eq "futex"; then
      FUTEX_THREADS=$((FUTEX_THREADS + 1))
    fi
  fi
done

if [ "$FUTEX_THREADS" -lt 2 ]; then
  echo "FAIL: Expected at least 2 worker threads blocked in futex wait channel, observed $FUTEX_THREADS"
  exit 1
fi

if [ ! -f "$REPORT_FILE" ]; then
  echo "FAIL: Diagnostic report $REPORT_FILE does not exist"
  exit 1
fi

REPORT_PID=$(grep "^SERVICE_PID=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
REPORT_TIDS=$(grep "^WORKER_TIDS=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
REPORT_WCHAN=$(grep "^WAIT_CHANNEL=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')
REPORT_STATE=$(grep "^THREAD_STATE=" "$REPORT_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ -z "$REPORT_PID" ] || [ "$REPORT_PID" != "$PID" ]; then
  echo "FAIL: SERVICE_PID in report ('$REPORT_PID') does not match active PID ($PID)"
  exit 1
fi

if [ -z "$REPORT_TIDS" ]; then
  echo "FAIL: WORKER_TIDS not specified in $REPORT_FILE"
  exit 1
fi

# Validate reported TIDs exist under /proc/$PID/task
IFS=',' read -ra TID_ARRAY <<< "$REPORT_TIDS"
if [ "${#TID_ARRAY[@]}" -lt 2 ]; then
  echo "FAIL: Expected at least 2 worker TIDs in WORKER_TIDS, got ${#TID_ARRAY[@]}"
  exit 1
fi

for tid in "${TID_ARRAY[@]}"; do
  tid=$(echo "$tid" | tr -d ' ')
  if [ ! -d "/proc/$PID/task/$tid" ]; then
    echo "FAIL: Reported TID $tid does not exist under /proc/$PID/task/"
    exit 1
  fi
done

if ! echo "$REPORT_WCHAN" | grep -Eq "futex"; then
  echo "FAIL: WAIT_CHANNEL ('$REPORT_WCHAN') must be a futex wait channel (e.g. futex_do_wait)"
  exit 1
fi

if ! echo "$REPORT_STATE" | grep -Eq "^S"; then
  echo "FAIL: THREAD_STATE ('$REPORT_STATE') must reflect sleeping state (e.g. Sl or S)"
  exit 1
fi

echo "PASS: Multi-thread deadlock and live futex wait states verified"
exit 0
