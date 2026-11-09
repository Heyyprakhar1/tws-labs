#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/shm-incident"
mkdir -p "$TARGET_DIR/bin" "$TARGET_DIR/config" "$TARGET_DIR/src" "$TARGET_DIR/var" "$TARGET_DIR/reports"

UID_VAL=$(id -u)

# 1. Clean any preexisting test/demo segments for this UID
python3 -c '
import _posixshmem
import os

uid = os.getuid()
sess = os.environ.get("TWS_SESSION_ID") or os.environ.get("LAB_SESSION_ID") or str(uid)
inst = os.environ.get("TWS_INSTANCE_ID")
prefixes = [f"tws_{inst}_{sess}", f"tws_{sess}", f"tws_{uid}"] if inst else [f"tws_{sess}", f"tws_{uid}"]
for seg in ["telemetry", "lifecycle_demo", "resilience"]:
    for prefix in prefixes:
        name = f"{prefix}_{seg}"
        try:
            _posixshmem.shm_unlink(name)
        except Exception:
            pass
        p = f"/dev/shm/{name}"
        if os.path.exists(p):
            try:
                os.unlink(p)
            except Exception:
                pass
'

# 2. Write telemetry configuration
cat << 'CONF_EOF' > "$TARGET_DIR/config/telemetry.env"
# Telemetry Collector Configuration
SEGMENT_NAME="telemetry"
SEGMENT_SIZE_BYTES=1048576
AUTO_UNLINK_ON_SHUTDOWN=false
DEFENSIVE_STARTUP_CLEANUP=false
CONF_EOF

# 3. Create telemetry daemon engine
cat << 'DAEMON_EOF' > "$TARGET_DIR/src/telemetry_daemon.py"
import os
import sys
import time
import signal
import threading
import mmap
import _posixshmem

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(BASE_DIR, "config", "telemetry.env")
PID_FILE = os.path.join(BASE_DIR, "var", "telemetry.pid")
LOG_FILE = os.path.join(BASE_DIR, "var", "telemetry.log")

def load_config():
    cfg = {
        "SEGMENT_NAME": "telemetry",
        "SEGMENT_SIZE_BYTES": "1048576",
        "AUTO_UNLINK_ON_SHUTDOWN": "false",
        "DEFENSIVE_STARTUP_CLEANUP": "false",
    }
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

running = True
shm_fd = None
shm_map = None
full_name = None

def watchdog():
    # Maximum runtime bound: 300s to avoid background process accumulation
    time.sleep(300)
    os._exit(0)

def sig_handler(signum, frame):
    global running, shm_fd, shm_map, full_name
    running = False
    cfg = load_config()
    auto_unlink = cfg.get("AUTO_UNLINK_ON_SHUTDOWN", "false").lower() == "true"
    if shm_map is not None:
        try:
            shm_map.close()
        except Exception:
            pass
    if shm_fd is not None:
        try:
            os.close(shm_fd)
        except Exception:
            pass
    if auto_unlink and full_name:
        try:
            _posixshmem.shm_unlink(full_name)
        except Exception:
            pass
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass
    os._exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, sig_handler)
    signal.signal(signal.SIGINT, sig_handler)

    wd = threading.Thread(target=watchdog, daemon=True, name="watchdog")
    wd.start()

    cfg = load_config()
    uid = os.getuid()
    seg_name = cfg.get("SEGMENT_NAME", "telemetry")
    sess_id = os.environ.get("TWS_SESSION_ID") or os.environ.get("LAB_SESSION_ID")
    inst_id = os.environ.get("TWS_INSTANCE_ID")
    if inst_id and sess_id:
        shm_prefix = f"tws_{inst_id}_{sess_id}"
    elif sess_id:
        shm_prefix = f"tws_{sess_id}"
    else:
        shm_prefix = f"tws_{uid}"
    full_name = f"{shm_prefix}_{seg_name}"
    size = int(cfg.get("SEGMENT_SIZE_BYTES", "1048576"))
    defensive_clean = cfg.get("DEFENSIVE_STARTUP_CLEANUP", "false").lower() == "true"

    if defensive_clean:
        try:
            _posixshmem.shm_unlink(full_name)
        except Exception:
            pass
        shm_path = f"/dev/shm/{full_name}"
        if os.path.exists(shm_path):
            try:
                os.unlink(shm_path)
            except Exception:
                pass

    try:
        shm_fd = _posixshmem.shm_open(full_name, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        os.ftruncate(shm_fd, size)
    except FileExistsError:
        if defensive_clean:
            try:
                _posixshmem.shm_unlink(full_name)
                shm_fd = _posixshmem.shm_open(full_name, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
                os.ftruncate(shm_fd, size)
            except Exception as e:
                print(f"Error recreating shm: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"Error: Segment {full_name} already exists in /dev/shm", file=sys.stderr)
            sys.exit(1)

    # Map into memory
    shm_map = mmap.mmap(shm_fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
    shm_map[0:4] = b"TWS1"

    while running:
        time.sleep(0.5)
DAEMON_EOF

# 4. Create demo daemon engine (for task 2 lifecycle inspection)
cat << 'DEMO_EOF' > "$TARGET_DIR/src/demo_daemon.py"
import os
import sys
import time
import signal
import threading
import mmap
import _posixshmem

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PID_FILE = os.path.join(BASE_DIR, "var", "demo.pid")

running = True
shm_fd = None
shm_map = None

def watchdog():
    time.sleep(120)
    os._exit(0)

def sig_handler(signum, frame):
    global running, shm_map, shm_fd
    running = False
    if shm_map is not None:
        try:
            shm_map.close()
        except Exception:
            pass
    if shm_fd is not None:
        try:
            os.close(shm_fd)
        except Exception:
            pass
    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass
    os._exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, sig_handler)
    signal.signal(signal.SIGINT, sig_handler)

    wd = threading.Thread(target=watchdog, daemon=True, name="watchdog")
    wd.start()

    uid = os.getuid()
    sess_id = os.environ.get("TWS_SESSION_ID") or os.environ.get("LAB_SESSION_ID")
    inst_id = os.environ.get("TWS_INSTANCE_ID")
    if inst_id and sess_id:
        shm_prefix = f"tws_{inst_id}_{sess_id}"
    elif sess_id:
        shm_prefix = f"tws_{sess_id}"
    else:
        shm_prefix = f"tws_{uid}"
    name = f"{shm_prefix}_lifecycle_demo"
    # Ensure fresh
    try:
        _posixshmem.shm_unlink(name)
    except Exception:
        pass

    # Create 4096-byte segment
    shm_fd = _posixshmem.shm_open(name, os.O_CREAT | os.O_RDWR, 0o600)
    os.ftruncate(shm_fd, 4096)
    shm_map = mmap.mmap(shm_fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
    shm_map[0:4] = b"DEMO"

    # Demonstrate POSIX unlinking: remove name from /dev/shm
    # The active mapping in memory remains retained by this process!
    _posixshmem.shm_unlink(name)

    while running:
        time.sleep(0.5)
DEMO_EOF

# 5. Write telemetry-ctl script
cat << 'CTL_EOF' > "$TARGET_DIR/bin/telemetry-ctl"
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$BASE_DIR/var/telemetry.pid"
LOG_FILE="$BASE_DIR/var/telemetry.log"
UID_VAL=$(id -u)
if [ -n "${TWS_INSTANCE_ID:-}" ] && [ -n "${TWS_SESSION_ID:-}" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_INSTANCE_ID}_${TWS_SESSION_ID}_telemetry"
elif [ -n "${TWS_SESSION_ID:-}" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_SESSION_ID}_telemetry"
else
  SHM_FILE="/dev/shm/tws_${UID_VAL}_telemetry"
fi

start_service() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "telemetry-collector is already running (PID: $(cat "$PID_FILE"))"
    return 0
  fi
  echo "Starting telemetry-collector..."
  nohup python3 "$BASE_DIR/src/telemetry_daemon.py" > "$LOG_FILE" 2>&1 &
  PID=$!
  echo "$PID" > "$PID_FILE"
  sleep 0.3
  if kill -0 "$PID" 2>/dev/null; then
    echo "telemetry-collector started successfully (PID: $PID)"
  else
    echo "Failed to start telemetry-collector. Check $LOG_FILE"
    exit 1
  fi
}

stop_service() {
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping telemetry-collector (PID: $PID)..."
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
    echo "telemetry-collector stopped."
  else
    echo "telemetry-collector is not running."
  fi
}

cleanup_shm() {
  if [ -e "$SHM_FILE" ]; then
    # Verify ownership before deletion
    OWNER=$(stat -c '%u' "$SHM_FILE" 2>/dev/null || echo "")
    if [ "$OWNER" = "$UID_VAL" ]; then
      rm -f "$SHM_FILE"
      echo "Reclaimed stale shared memory segment: $SHM_FILE"
    else
      echo "Error: $SHM_FILE is not owned by UID $UID_VAL"
      exit 1
    fi
  else
    echo "No stale shared memory segment found at $SHM_FILE"
  fi
}

status_service() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    PID=$(cat "$PID_FILE")
    echo "telemetry-collector is running (PID: $PID)"
    echo "Shared memory status:"
    ls -lh "$SHM_FILE" 2>/dev/null || echo "Segment not currently visible in /dev/shm"
  else
    echo "telemetry-collector is stopped."
    echo "Shared memory status:"
    ls -lh "$SHM_FILE" 2>/dev/null || echo "No segment present in /dev/shm"
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
  cleanup)
    cleanup_shm
    ;;
  status)
    status_service
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|cleanup|status}"
    exit 1
    ;;
esac
CTL_EOF
chmod +x "$TARGET_DIR/bin/telemetry-ctl"

# 6. Write demo-lifecycle script
cat << 'DEMO_CTL_EOF' > "$TARGET_DIR/bin/demo-lifecycle"
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$BASE_DIR/var/demo.pid"
LOG_FILE="$BASE_DIR/var/demo.log"

case "${1:-}" in
  start)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      echo "demo-daemon is already running (PID: $(cat "$PID_FILE"))"
      exit 0
    fi
    nohup python3 "$BASE_DIR/src/demo_daemon.py" > "$LOG_FILE" 2>&1 &
    PID=$!
    echo "$PID" > "$PID_FILE"
    sleep 0.2
    echo "demo-daemon started (PID: $PID)"
    ;;
  stop)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      kill -15 "$PID" 2>/dev/null || true
      rm -f "$PID_FILE"
      echo "demo-daemon stopped."
    fi
    ;;
  status)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      PID=$(cat "$PID_FILE")
      echo "demo-daemon running (PID: $PID)"
    else
      echo "demo-daemon stopped."
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
DEMO_CTL_EOF
chmod +x "$TARGET_DIR/bin/demo-lifecycle"

# 7. Write verify-shm-resilience script
cat << 'VERIFY_EOF' > "$TARGET_DIR/bin/verify-shm-resilience"
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="$BASE_DIR/config/telemetry.env"
REPORT_FILE="$BASE_DIR/reports/recovery-report.env"
UID_VAL=$(id -u)
if [ -n "${TWS_INSTANCE_ID:-}" ] && [ -n "${TWS_SESSION_ID:-}" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_INSTANCE_ID}_${TWS_SESSION_ID}_telemetry"
elif [ -n "${TWS_SESSION_ID:-}" ]; then
  SHM_FILE="/dev/shm/tws_${TWS_SESSION_ID}_telemetry"
else
  SHM_FILE="/dev/shm/tws_${UID_VAL}_telemetry"
fi

echo "=== Verifying POSIX Shared Memory Resilience ==="

# Check config requirements
AUTO_UNLINK=$(grep "^AUTO_UNLINK_ON_SHUTDOWN=" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')
DEFENSIVE=$(grep "^DEFENSIVE_STARTUP_CLEANUP=" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' "')

if [ "$AUTO_UNLINK" != "true" ] || [ "$DEFENSIVE" != "true" ]; then
  echo "FAIL: AUTO_UNLINK_ON_SHUTDOWN and DEFENSIVE_STARTUP_CLEANUP must both be true in config/telemetry.env"
  exit 1
fi

# Stop any running daemon first
"$BASE_DIR/bin/telemetry-ctl" stop >/dev/null 2>&1 || true

# Test 1: Graceful shutdown test
echo "[Test 1] Starting daemon and testing graceful SIGTERM unlinking..."
"$BASE_DIR/bin/telemetry-ctl" start >/dev/null 2>&1
sleep 0.3

if [ ! -e "$SHM_FILE" ]; then
  echo "FAIL: Shared memory object was not created at $SHM_FILE"
  exit 1
fi

"$BASE_DIR/bin/telemetry-ctl" stop >/dev/null 2>&1
sleep 0.3

if [ -e "$SHM_FILE" ]; then
  echo "FAIL: Stale shared memory object persisted after graceful SIGTERM stop!"
  exit 1
fi
echo "[Test 1 PASS] Graceful SIGTERM cleanly unlinked shared memory."

# Test 2: Crash recovery test (simulate SIGKILL leaving stale object)
echo "[Test 2] Simulating unhandled crash (SIGKILL) followed by defensive startup..."
"$BASE_DIR/bin/telemetry-ctl" start >/dev/null 2>&1
sleep 0.3
PID=$(cat "$BASE_DIR/var/telemetry.pid")
# Forcibly kill with SIGKILL to simulate crash
kill -9 "$PID" 2>/dev/null || true
rm -f "$BASE_DIR/var/telemetry.pid"

if [ ! -e "$SHM_FILE" ]; then
  echo "FAIL: Expected stale object to remain after SIGKILL"
  exit 1
fi

# Now start daemon again; defensive cleanup should reclaim stale object and start cleanly
"$BASE_DIR/bin/telemetry-ctl" start >/dev/null 2>&1
sleep 0.3

if ! "$BASE_DIR/bin/telemetry-ctl" status >/dev/null 2>&1; then
  echo "FAIL: Daemon failed to start when recovering from stale segment"
  exit 1
fi

"$BASE_DIR/bin/telemetry-ctl" stop >/dev/null 2>&1

mkdir -p "$BASE_DIR/reports"
cat << RPT_EOF > "$REPORT_FILE"
VERIFICATION_STATUS=SUCCESS
LEAKS_DETECTED=0
CLEANUP_STRATEGY=DEFENSIVE_STARTUP_AND_SIGTERM_UNLINK
MAX_ALLOCATION_BYTES=1052672
RPT_EOF

echo "Verification report written to $REPORT_FILE"
echo "=== All Resilience Tests Passed ==="
VERIFY_EOF
chmod +x "$TARGET_DIR/bin/verify-shm-resilience"

# 8. Create initial simulated leaked segment (1 MB, unhandled crash) using _posixshmem
python3 -c '
import _posixshmem
import os

uid = os.getuid()
sess_id = os.environ.get("TWS_SESSION_ID") or os.environ.get("LAB_SESSION_ID")
inst_id = os.environ.get("TWS_INSTANCE_ID")
if inst_id and sess_id:
    name = f"tws_{inst_id}_{sess_id}_telemetry"
elif sess_id:
    name = f"tws_{sess_id}_telemetry"
else:
    name = f"tws_{uid}_telemetry"
# Clean preexisting
try:
    _posixshmem.shm_unlink(name)
except Exception:
    pass

# Create 1 MB segment (1048576 bytes)
fd = _posixshmem.shm_open(name, os.O_CREAT | os.O_RDWR, 0o600)
os.ftruncate(fd, 1048576)
os.write(fd, b"LEAK")
os.close(fd)
'

echo "LNX-CH-208 environment initialized with orphaned 1 MB shared memory segment."
