#!/bin/bash
set -euo pipefail

# 1. Base Resolution
SELECTED_BASE=""
if [ -n "${LAB_HOME:-}" ] && [ -d "$LAB_HOME" ]; then
  SELECTED_BASE="$LAB_HOME"
elif [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
  SELECTED_BASE="$HOME"
else
  echo "Fatal: Neither LAB_HOME nor HOME points to a valid existing directory." >&2
  exit 1
fi

CANONICAL_BASE="$(realpath -e "$SELECTED_BASE" 2>/dev/null)" || {
  echo "Fatal: Failed to resolve canonical base directory for: $SELECTED_BASE" >&2
  exit 1
}

case "$CANONICAL_BASE" in
  /|/home|/root|/tmp|/var|/usr|/bin|/etc)
    echo "Fatal: Base directory cannot be a top-level system mount: $CANONICAL_BASE" >&2
    exit 1
    ;;
esac

INCIDENT_ROOT="$CANONICAL_BASE/spool-incident"

# Teardown any existing processes if directory exists
if [ -d "$INCIDENT_ROOT" ]; then
  if [ -f "$INCIDENT_ROOT/var/run/spooler.pid" ]; then
    PID=$(cat "$INCIDENT_ROOT/var/run/spooler.pid" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      kill -TERM "$PID" 2>/dev/null || true
      sleep 0.2
      kill -KILL "$PID" 2>/dev/null || true
    fi
  fi
fi

rm -rf "$INCIDENT_ROOT"
mkdir -p "$INCIDENT_ROOT/bin" \
         "$INCIDENT_ROOT/config" \
         "$INCIDENT_ROOT/logs" \
         "$INCIDENT_ROOT/reports" \
         "$INCIDENT_ROOT/var/run" \
         "$INCIDENT_ROOT/var/spool"

# 2. Defective Spooler Configuration
cat << 'EOF' > "$INCIDENT_ROOT/config/spooler.env"
# Event Spooler Service Configuration
SERVICE_NAME=event-spooler
MAX_SPOOL_FILES=1000
AUTO_PURGE_ENABLED=false
SPOOL_DIR=var/spool
LOG_LEVEL=info
EOF
chmod 0644 "$INCIDENT_ROOT/config/spooler.env"

# 3. Spooler Daemon Script
cat << 'DAEMON_EOF' > "$INCIDENT_ROOT/bin/spool-daemon"
#!/usr/bin/env python3
import os
import sys
import time
import signal

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONFIG_FILE = os.path.join(BASE_DIR, 'config', 'spooler.env')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'spooler.log')
PID_FILE = os.path.join(BASE_DIR, 'var', 'run', 'spooler.pid')
READY_FILE = os.path.join(BASE_DIR, 'var', 'run', '.ready')
STATUS_FILE = os.path.join(BASE_DIR, 'var', 'run', 'status.env')

running = True
def handle_sig(sig, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

with open(PID_FILE, 'w') as f:
    f.write(str(os.getpid()) + '\n')

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{ts}] {msg}\n")

def read_config():
    cfg = {'MAX_SPOOL_FILES': 1000, 'AUTO_PURGE_ENABLED': 'false', 'SPOOL_DIR': 'var/spool'}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

log("Starting event-spooler daemon (PID %d)" % os.getpid())

with open(READY_FILE, 'w') as f:
    f.write('ready\n')

while running:
    cfg = read_config()
    max_files = int(cfg.get('MAX_SPOOL_FILES', 1000))
    auto_purge = cfg.get('AUTO_PURGE_ENABLED', 'false').lower() == 'true'
    spool_dir = os.path.join(BASE_DIR, cfg.get('SPOOL_DIR', 'var/spool'))

    try:
        current_count = len(os.listdir(spool_dir))
    except Exception:
        current_count = 0

    if current_count > max_files:
        status = "EXCEEDED"
        log(f"[ERROR] Ingestion halted: ENOSPC (spool quota {max_files} exceeded; {current_count} files staged)")
    else:
        status = "HEALTHY"
        if auto_purge and current_count > 0:
            log(f"[INFO] Auto-purge active: processing {current_count} staging files")

    with open(STATUS_FILE, 'w') as f:
        f.write(f"SERVICE_NAME=event-spooler\nSTATUS={status}\nCURRENT_COUNT={current_count}\nMAX_FILES={max_files}\nAUTO_PURGE={auto_purge}\n")

    time.sleep(1)

log("Stopping event-spooler daemon")
if os.path.exists(PID_FILE):
    try: os.remove(PID_FILE)
    except: pass
if os.path.exists(READY_FILE):
    try: os.remove(READY_FILE)
    except: pass
DAEMON_EOF
chmod 0755 "$INCIDENT_ROOT/bin/spool-daemon"

# 4. Spooler Control Script
cat << 'CTL_EOF' > "$INCIDENT_ROOT/bin/spool-ctl"
#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$BASE_DIR/var/run/spooler.pid"
READY_FILE="$BASE_DIR/var/run/.ready"
STATUS_FILE="$BASE_DIR/var/run/status.env"
DAEMON="$BASE_DIR/bin/spool-daemon"

cmd="${1:-status}"

case "$cmd" in
  start)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "event-spooler is already running (PID $PID)"
        exit 0
      fi
    fi
    rm -f "$READY_FILE"
    nohup "$DAEMON" >/dev/null 2>&1 &
    for i in $(seq 1 30); do
      if [ -f "$READY_FILE" ]; then break; fi
      sleep 0.1
    done
    echo "event-spooler started (PID $(cat "$PID_FILE" 2>/dev/null || echo unknown))"
    ;;
  stop)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        for i in $(seq 1 20); do
          if ! kill -0 "$PID" 2>/dev/null; then break; fi
          sleep 0.1
        done
        kill -KILL "$PID" 2>/dev/null || true
      fi
      rm -f "$PID_FILE" "$READY_FILE"
      echo "event-spooler stopped"
    else
      echo "event-spooler not running"
    fi
    ;;
  restart)
    "$0" stop
    sleep 0.2
    "$0" start
    ;;
  status)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "event-spooler: active (running, PID $PID)"
        if [ -f "$STATUS_FILE" ]; then
          cat "$STATUS_FILE"
        fi
        exit 0
      fi
    fi
    echo "event-spooler: inactive (dead)"
    exit 1
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
CTL_EOF
chmod 0755 "$INCIDENT_ROOT/bin/spool-ctl"

# 5. Verification Tool
cat << 'VERIFY_EOF' > "$INCIDENT_ROOT/bin/verify-spool"
#!/usr/bin/env python3
import os
import sys
import hashlib
import time

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONFIG_FILE = os.path.join(BASE_DIR, 'config', 'spooler.env')
SPOOL_DIR = os.path.join(BASE_DIR, 'var', 'spool')
PID_FILE = os.path.join(BASE_DIR, 'var', 'run', 'spooler.pid')
MARKER_FILE = os.path.join(BASE_DIR, 'reports', 'verification.marker')

# 1. Check daemon running
if not os.path.exists(PID_FILE):
    print("Verification failed: event-spooler is not running.")
    sys.exit(1)

with open(PID_FILE) as f:
    pid = int(f.read().strip())

try:
    os.kill(pid, 0)
except OSError:
    print("Verification failed: event-spooler process is dead.")
    sys.exit(1)

# 2. Check configuration
cfg = {}
with open(CONFIG_FILE) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            cfg[k.strip()] = v.strip().strip('"').strip("'")

max_files = int(cfg.get('MAX_SPOOL_FILES', 0))
auto_purge = cfg.get('AUTO_PURGE_ENABLED', '').lower() == 'true'

if max_files < 5000:
    print(f"Verification failed: MAX_SPOOL_FILES must be at least 5000 (currently {max_files}).")
    sys.exit(1)

if not auto_purge:
    print("Verification failed: AUTO_PURGE_ENABLED must be set to true.")
    sys.exit(1)

# 3. Check spool directory file count
remaining_files = len(os.listdir(SPOOL_DIR))
if remaining_files > 50:
    print(f"Verification failed: var/spool still contains {remaining_files} files (must be <= 50).")
    sys.exit(1)

# 4. Simulate test ingestion
for i in range(25):
    fname = f"test_event_{i:03d}.tmp"
    with open(os.path.join(SPOOL_DIR, fname), 'w') as f:
        f.write("event_payload\n")

time.sleep(1.2)

# 5. Write signed marker
ts = str(int(time.time()))
raw = f"SPOOL_VERIFIED:{pid}:{max_files}:{auto_purge}:{ts}".encode('utf-8')
token = hashlib.sha256(raw).hexdigest()

with open(MARKER_FILE, 'w') as f:
    f.write(f"VERIFICATION_STATUS=PASSED\nVERIFICATION_TOKEN={token}\nVERIFIED_PID={pid}\nMAX_FILES={max_files}\nREMAINING_SPOOL_FILES={remaining_files}\n")

print("Verification PASSED: Spool capacity restored, limits verified, audit marker created.")
sys.exit(0)
VERIFY_EOF
chmod 0755 "$INCIDENT_ROOT/bin/verify-spool"

# 6. Generate 10,000 long-named files (245 bytes) to reproduce ARG_MAX E2BIG
python3 -c "
import os
spool_dir = '$INCIDENT_ROOT/var/spool'
padding = 'a' * 229
for i in range(10000):
    fname = f'batch_{i:05d}_{padding}.dat'
    open(os.path.join(spool_dir, fname), 'w').close()
"

# 7. Start Spooler Daemon
"$INCIDENT_ROOT/bin/spool-ctl" start >/dev/null 2>&1
