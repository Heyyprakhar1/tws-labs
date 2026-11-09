#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/deadlock-incident"
mkdir -p "$TARGET_DIR/bin" "$TARGET_DIR/config" "$TARGET_DIR/src" "$TARGET_DIR/traces" "$TARGET_DIR/var" "$TARGET_DIR/reports"

# 1. Write reference syscall trace
cat << 'TRACE_EOF' > "$TARGET_DIR/traces/deadlock-strace.log"
# ==============================================================================
# PRE-CAPTURED DIAGNOSTIC SYSCALL TRACE (SUPPLIED REFERENCE ARTIFACT)
# ==============================================================================
# NOTE: In hardened container environments, ptrace(2) and live strace capture
# are restricted by security policy (CAP_SYS_PTRACE dropped).
# This trace was captured in a reference staging environment to illustrate the
# low-level futex(2) syscall arguments and lock address collisions during the incident.
#
# Workload: order-processor with 2 worker threads handling bidirectional transfers
# between Account 101 (Mutex A: 0x7f8a94000b00) and Account 102 (Mutex B: 0x7f8a94000b20)
# ==============================================================================
[pid 1041] clone3({flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, child_tid=0x7f8a93fff910, parent_tid=0x7f8a93fff910, exit_signal=0, stack=0x7f8a937ff000, stack_size=0x800000, tls=0x7f8a93fff700}, 88) = 1042
[pid 1041] clone3({flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, child_tid=0x7f8a92fff910, parent_tid=0x7f8a92fff910, exit_signal=0, stack=0x7f8a927ff000, stack_size=0x800000, tls=0x7f8a92fff700}, 88) = 1043
[pid 1042] [worker-1] Acquired Lock 101 (0x7f8a94000b00)
[pid 1043] [worker-2] Acquired Lock 102 (0x7f8a94000b20)
[pid 1042] [worker-1] Requesting Lock 102 (0x7f8a94000b20)... Contended!
[pid 1042] futex(0x7f8a94000b20, FUTEX_WAIT_BITSET_PRIVATE|FUTEX_CLOCK_REALTIME, 0, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
[pid 1043] [worker-2] Requesting Lock 101 (0x7f8a94000b00)... Contended!
[pid 1043] futex(0x7f8a94000b00, FUTEX_WAIT_BITSET_PRIVATE|FUTEX_CLOCK_REALTIME, 0, NULL, FUTEX_BITSET_MATCH_ANY <unfinished ...>
# DIAGNOSIS: AB-BA lock inversion. Thread 1042 waits on 0x7f8a94000b20 held by 1043.
# Thread 1043 waits on 0x7f8a94000b00 held by 1042. Circular wait condition.
TRACE_EOF

# 2. Write initial service configuration
cat << 'CONF_EOF' > "$TARGET_DIR/config/service.env"
# Order Processor Configuration
ORDER_LOCKS_BY_ID=false
WORKER_THREADS=2
ACCOUNT_A_ID=101
ACCOUNT_B_ID=102
SERVICE_PORT=8443
CONF_EOF

# 3. Write core processor engine
cat << 'ENGINE_EOF' > "$TARGET_DIR/src/processor.py"
import os
import sys
import time
import signal
import threading

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(BASE_DIR, "config", "service.env")
PID_FILE = os.path.join(BASE_DIR, "var", "service.pid")

def load_config():
    cfg = {"ORDER_LOCKS_BY_ID": "false"}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

lock_101 = threading.Lock()
lock_102 = threading.Lock()
account_locks = {101: lock_101, 102: lock_102}

running = True
processed_counter = 0
counter_lock = threading.Lock()

def worker_transfer(worker_name, from_acct, to_acct, order_locks):
    global running, processed_counter
    # Determine lock acquisition sequence
    if order_locks:
        # Hierarchical lock acquisition: acquire lowest ID first
        low_id = min(from_acct, to_acct)
        high_id = max(from_acct, to_acct)
        first_lock = account_locks[low_id]
        second_lock = account_locks[high_id]
    else:
        # Unconstrained lock acquisition: acquire source then destination
        first_lock = account_locks[from_acct]
        second_lock = account_locks[to_acct]

    while running:
        with first_lock:
            # Short sleep to guarantee deterministic interleaving on initial defect
            time.sleep(0.05)
            with second_lock:
                with counter_lock:
                    processed_counter += 1
                time.sleep(0.02)
        if not order_locks:
            # In unconstrained mode, the two threads deadlock on the very first transfer
            time.sleep(1)

def watchdog():
    # Terminate after 300s to avoid background process accumulation
    time.sleep(300)
    os._exit(0)

def sig_handler(signum, frame):
    global running
    running = False
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass
    os._exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, sig_handler)
    signal.signal(signal.SIGINT, sig_handler)

    # Watchdog thread
    wd = threading.Thread(target=watchdog, daemon=True, name="watchdog")
    wd.start()

    cfg = load_config()
    order_by_id = cfg.get("ORDER_LOCKS_BY_ID", "false").lower() == "true"

    t1 = threading.Thread(target=worker_transfer, args=("worker-101-to-102", 101, 102, order_by_id), name="worker-tx-1")
    t2 = threading.Thread(target=worker_transfer, args=("worker-102-to-101", 102, 101, order_by_id), name="worker-tx-2")

    t1.start()
    t2.start()

    # Main thread supervisor loop
    while running:
        time.sleep(0.5)
ENGINE_EOF

# 4. Write order-processor executable wrapper
cat << 'BIN_EOF' > "$TARGET_DIR/bin/order-processor"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$DIR/src/processor.py"
BIN_EOF
chmod +x "$TARGET_DIR/bin/order-processor"

# 5. Write control script
cat << 'CTL_EOF' > "$TARGET_DIR/bin/order-ctl"
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$BASE_DIR/var/service.pid"
LOG_FILE="$BASE_DIR/var/service.log"

get_pid() {
  if [ -f "$PID_FILE" ]; then
    cat "$PID_FILE"
  fi
}

start_service() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "order-processor is already running (PID: $(cat "$PID_FILE"))"
    return 0
  fi
  echo "Starting order-processor..."
  nohup "$BASE_DIR/bin/order-processor" > "$LOG_FILE" 2>&1 &
  PID=$!
  echo "$PID" > "$PID_FILE"
  # Allow initial lock acquisition to establish state
  sleep 0.3
  if kill -0 "$PID" 2>/dev/null; then
    echo "order-processor started successfully (PID: $PID)"
  else
    echo "Failed to start order-processor"
    exit 1
  fi
}

stop_service() {
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping order-processor (PID: $PID)..."
      kill -15 "$PID" 2>/dev/null || true
      for i in {1..20}; do
        if ! kill -0 "$PID" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
      if kill -0 "$PID" 2>/dev/null; then
        echo "Escalating to SIGKILL..."
        kill -9 "$PID" 2>/dev/null || true
      fi
    fi
    rm -f "$PID_FILE"
    echo "order-processor stopped."
  else
    echo "order-processor is not running."
  fi
}

status_service() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    PID=$(cat "$PID_FILE")
    echo "order-processor is running (PID: $PID)"
    echo "--- Active Threads ---"
    ps -T -p "$PID" -o pid,tid,stat,wchan:20,comm || true
  else
    echo "order-processor is stopped."
    return 1
  fi
}

case "${1:-}" in
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    stop_service
    start_service
    ;;
  status)
    status_service
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
CTL_EOF
chmod +x "$TARGET_DIR/bin/order-ctl"

# 6. Write benchmark tool
cat << 'BENCH_EOF' > "$TARGET_DIR/bin/benchmark-concurrency"
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="$BASE_DIR/config/service.env"
PID_FILE="$BASE_DIR/var/service.pid"
REPORT_FILE="$BASE_DIR/reports/recovery-report.env"

echo "Executing Concurrent Transaction Benchmark (50 transactions)..."

if [ ! -f "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Error: order-processor service is not running."
  exit 1
fi

PID=$(cat "$PID_FILE")

# Check if order-processor is configured with deterministic lock ordering
ORDERING=$(grep "ORDER_LOCKS_BY_ID" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$ORDERING" != "true" ]; then
  echo "Benchmark failed: ORDER_LOCKS_BY_ID is not enabled in config/service.env"
  exit 1
fi

# Run python benchmark harness
python3 -c '
import threading, time, sys

lock_a = threading.Lock()
lock_b = threading.Lock()
account_locks = {101: lock_a, 102: lock_b}
completed = 0
c_lock = threading.Lock()

def tx(from_id, to_id):
    global completed
    low_id = min(from_id, to_id)
    high_id = max(from_id, to_id)
    first = account_locks[low_id]
    second = account_locks[high_id]
    with first:
        time.sleep(0.002)
        with second:
            with c_lock:
                completed += 1

threads = []
for i in range(50):
    src, dst = (101, 102) if i % 2 == 0 else (102, 101)
    t = threading.Thread(target=tx, args=(src, dst))
    threads.append(t)
    t.start()

for t in threads:
    t.join(timeout=2.0)
    if t.is_alive():
        print("ERROR: Benchmark thread hung in futex wait (deadlock)!")
        sys.exit(1)

if completed != 50:
    print(f"ERROR: Expected 50 completed transactions, got {completed}")
    sys.exit(1)

print(f"Benchmark completed successfully: {completed} transactions processed, 0 deadlocks.")
'

mkdir -p "$BASE_DIR/reports"
cat << RECOVERY_EOF > "$REPORT_FILE"
BENCHMARK_STATUS=SUCCESS
TRANSFERS_COMPLETED=50
DEADLOCKS_DETECTED=0
LOCK_ORDERING=DETERMINISTIC
RECOVERY_EOF

echo "Recovery report written to $REPORT_FILE"
BENCH_EOF
chmod +x "$TARGET_DIR/bin/benchmark-concurrency"

# Clean any preexisting daemon for this user and start initial deadlocked service
"$TARGET_DIR/bin/order-ctl" stop >/dev/null 2>&1 || true
"$TARGET_DIR/bin/order-ctl" start >/dev/null 2>&1
echo "LNX-CH-207 environment initialized."
