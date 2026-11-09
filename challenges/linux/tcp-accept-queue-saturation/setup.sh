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

INCIDENT_ROOT="$CANONICAL_BASE/tcp-incident"

# Dynamic port allocation per session UID
DEFAULT_PORT="18202"
if [ -n "${PORT_TCP:-}" ]; then
  ASSIGNED_PORT="$PORT_TCP"
elif [ -n "${UID:-}" ] && [ "$UID" -ge 10000 ]; then
  ASSIGNED_PORT=$((18200 + (UID - 10000)))
else
  ASSIGNED_PORT="$DEFAULT_PORT"
fi

# Teardown existing processes if directory exists
if [ -d "$INCIDENT_ROOT" ]; then
  if [ -f "$INCIDENT_ROOT/var/run/api-server.pid" ]; then
    PID=$(cat "$INCIDENT_ROOT/var/run/api-server.pid" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      kill -TERM "$PID" 2>/dev/null || true
      sleep 0.2
      kill -KILL "$PID" 2>/dev/null || true
    fi
  fi
  if [ -f "$INCIDENT_ROOT/var/run/clients.pid" ]; then
    CPID=$(cat "$INCIDENT_ROOT/var/run/clients.pid" 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$CPID" ] && kill -0 "$CPID" 2>/dev/null; then
      kill -KILL "$CPID" 2>/dev/null || true
    fi
  fi
fi

rm -rf "$INCIDENT_ROOT"
mkdir -p "$INCIDENT_ROOT/bin" \
         "$INCIDENT_ROOT/config" \
         "$INCIDENT_ROOT/logs" \
         "$INCIDENT_ROOT/reports" \
         "$INCIDENT_ROOT/var/run"

# 2. Defective Service Configuration
cat << EOF > "$INCIDENT_ROOT/config/api.env"
# Edge API Gateway TCP Configuration
SERVICE_NAME=api-gateway
PORT=$ASSIGNED_PORT
TCP_BACKLOG=5
WORKER_CONCURRENCY=1
LOG_LEVEL=info
EOF
chmod 0644 "$INCIDENT_ROOT/config/api.env"

# 3. API Server Implementation
cat << 'SERVER_EOF' > "$INCIDENT_ROOT/bin/api-server"
#!/usr/bin/env python3
import os
import sys
import time
import socket
import signal
from concurrent.futures import ThreadPoolExecutor

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONFIG_FILE = os.path.join(BASE_DIR, 'config', 'api.env')
LOG_FILE = os.path.join(BASE_DIR, 'logs', 'api-server.log')
PID_FILE = os.path.join(BASE_DIR, 'var', 'run', 'api-server.pid')
READY_FILE = os.path.join(BASE_DIR, 'var', 'run', '.ready')

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{ts}] {msg}\n")

def read_config():
    cfg = {'PORT': 18202, 'TCP_BACKLOG': 5, 'WORKER_CONCURRENCY': 1}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

cfg = read_config()
port = int(cfg.get('PORT', 18202))
backlog = int(cfg.get('TCP_BACKLOG', 5))
concurrency = int(cfg.get('WORKER_CONCURRENCY', 1))

with open(PID_FILE, 'w') as f:
    f.write(str(os.getpid()) + '\n')

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port))
srv.listen(backlog)

log(f"Server started on 127.0.0.1:{port} with backlog={backlog}, concurrency={concurrency} (PID {os.getpid()})")

with open(READY_FILE, 'w') as f:
    f.write('ready\n')

running = True
def handle_sig(sig, frame):
    global running
    running = False
    try: srv.close()
    except: pass

signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

def handle_client(conn, addr):
    try:
        conn.settimeout(2.0)
        data = conn.recv(1024)
        resp = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
        conn.sendall(resp)
    except Exception:
        pass
    finally:
        try: conn.close()
        except: pass

if concurrency <= 1:
    # Accept loop withheld / blocked: single worker thread is unresponsive/frozen
    # Completed 3-way handshakes accumulate in kernel Accept Queue indefinitely
    log(f"Server event loop blocked (concurrency={concurrency}): withholding accept() calls")
    while running:
        try:
            time.sleep(0.5)
        except OSError:
            break
else:
    # Fast multi-threaded accept loop
    pool = ThreadPoolExecutor(max_workers=concurrency)
    while running:
        try:
            conn, addr = srv.accept()
            pool.submit(handle_client, conn, addr)
        except OSError:
            break
    pool.shutdown(wait=False)

log("Server stopped.")
if os.path.exists(PID_FILE):
    try: os.remove(PID_FILE)
    except: pass
if os.path.exists(READY_FILE):
    try: os.remove(READY_FILE)
    except: pass
SERVER_EOF
chmod 0755 "$INCIDENT_ROOT/bin/api-server"

# 4. Service Control Script
cat << 'CTL_EOF' > "$INCIDENT_ROOT/bin/api-ctl"
#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$BASE_DIR/var/run/api-server.pid"
READY_FILE="$BASE_DIR/var/run/.ready"
CLIENTS_PID_FILE="$BASE_DIR/var/run/clients.pid"
DAEMON="$BASE_DIR/bin/api-server"
CONFIG="$BASE_DIR/config/api.env"

cmd="${1:-status}"

case "$cmd" in
  start)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "api-gateway is already running (PID $PID)"
        exit 0
      fi
    fi
    rm -f "$READY_FILE"
    nohup "$DAEMON" >/dev/null 2>&1 &
    for i in $(seq 1 30); do
      if [ -f "$READY_FILE" ]; then break; fi
      sleep 0.1
    done
    echo "api-gateway started (PID $(cat "$PID_FILE" 2>/dev/null || echo unknown))"
    ;;
  stop)
    if [ -f "$CLIENTS_PID_FILE" ]; then
      CPID=$(cat "$CLIENTS_PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$CPID" ] && kill -0 "$CPID" 2>/dev/null; then
        kill -KILL "$CPID" 2>/dev/null || true
      fi
      rm -f "$CLIENTS_PID_FILE"
    fi
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
      echo "api-gateway stopped"
    else
      echo "api-gateway not running"
    fi
    ;;
  restart)
    "$0" stop
    sleep 0.3
    "$0" start
    ;;
  status)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        PORT=$(grep -E '^PORT=' "$CONFIG" | cut -d= -f2 | tr -d '[:space:]"')
        BACKLOG=$(grep -E '^TCP_BACKLOG=' "$CONFIG" | cut -d= -f2 | tr -d '[:space:]"')
        echo "api-gateway: active (running, PID $PID, PORT $PORT, BACKLOG $BACKLOG)"
        exit 0
      fi
    fi
    echo "api-gateway: inactive (dead)"
    exit 1
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
CTL_EOF
chmod 0755 "$INCIDENT_ROOT/bin/api-ctl"

# 5. Netstat Metrics Tool
cat << 'NETSTAT_EOF' > "$INCIDENT_ROOT/bin/netstat-metrics"
#!/usr/bin/env python3
import sys

def get_netstat():
    try:
        with open("/proc/net/netstat") as f:
            lines = [line.strip().split() for line in f if line.startswith("TcpExt:")]
        if len(lines) < 2:
            return 0, 0
        headers = lines[0][1:]
        values = [int(v) for v in lines[1][1:]]
        d = dict(zip(headers, values))
        return d.get("ListenOverflows", 0), d.get("ListenDrops", 0)
    except Exception:
        return 0, 0

lo, ld = get_netstat()
print(f"ListenOverflows: {lo}")
print(f"ListenDrops: {ld}")
NETSTAT_EOF
chmod 0755 "$INCIDENT_ROOT/bin/netstat-metrics"

# 6. Burst Client Tool
cat << 'BURST_EOF' > "$INCIDENT_ROOT/bin/burst-client"
#!/usr/bin/env python3
import os
import sys
import socket
import time
import subprocess

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONFIG_FILE = os.path.join(BASE_DIR, 'config', 'api.env')

port = 18202
if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE) as f:
        for line in f:
            if line.startswith('PORT='):
                port = int(line.split('=', 1)[1].strip())

count = int(sys.argv[1]) if len(sys.argv) > 1 else 20

# If pre-seeded client holder is holding connections, release it and restart service
# so the burst starts from an empty queue and measures genuine queue filling + overflow
clients_pid_file = os.path.join(BASE_DIR, 'var', 'run', 'clients.pid')
if os.path.exists(clients_pid_file):
    try:
        with open(clients_pid_file) as pf:
            cpid = int(pf.read().strip())
        os.kill(cpid, 9)
    except:
        pass
    try:
        os.remove(clients_pid_file)
    except:
        pass
    ctl = os.path.join(BASE_DIR, 'bin', 'api-ctl')
    subprocess.run([ctl, 'restart'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

print(f"Firing {count} burst connections to 127.0.0.1:{port}...")
clients = []
success = 0
dropped = 0

for i in range(count):
    c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    c.settimeout(0.5)
    try:
        c.connect(('127.0.0.1', port))
        clients.append(c)
        success += 1
    except Exception:
        dropped += 1
        try: c.close()
        except: pass

time.sleep(0.3)
print(f"Burst completed: {success} succeeded, {dropped} dropped/timed out.")

# Keep connections open briefly then release
for c in clients:
    try: c.close()
    except: pass
BURST_EOF
chmod 0755 "$INCIDENT_ROOT/bin/burst-client"

# 7. Verification Audit Tool
cat << 'VERIFY_EOF' > "$INCIDENT_ROOT/bin/verify-backlog"
#!/usr/bin/env python3
import os
import sys
import socket
import time
import hashlib
import subprocess

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONFIG_FILE = os.path.join(BASE_DIR, 'config', 'api.env')
PID_FILE = os.path.join(BASE_DIR, 'var', 'run', 'api-server.pid')
MARKER_FILE = os.path.join(BASE_DIR, 'reports', 'verification.marker')

# 1. Verify process is running
if not os.path.exists(PID_FILE):
    print("Verification failed: api-gateway is not running.")
    sys.exit(1)

with open(PID_FILE) as f:
    pid = int(f.read().strip())

try:
    os.kill(pid, 0)
except OSError:
    print("Verification failed: api-gateway process is dead.")
    sys.exit(1)

# 2. Check configuration
cfg = {}
with open(CONFIG_FILE) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            cfg[k.strip()] = v.strip().strip('"').strip("'")

port = int(cfg.get('PORT', 18202))
backlog = int(cfg.get('TCP_BACKLOG', 0))
concurrency = int(cfg.get('WORKER_CONCURRENCY', 1))

if backlog < 128:
    print(f"Verification failed: TCP_BACKLOG must be at least 128 (currently {backlog}).")
    sys.exit(1)

if concurrency < 16:
    print(f"Verification failed: WORKER_CONCURRENCY must be at least 16 (currently {concurrency}).")
    sys.exit(1)

def get_netstat():
    try:
        with open("/proc/net/netstat") as f:
            lines = [line.strip().split() for line in f if line.startswith("TcpExt:")]
        if len(lines) < 2: return 0, 0
        headers = lines[0][1:]
        values = [int(v) for v in lines[1][1:]]
        d = dict(zip(headers, values))
        return d.get("ListenOverflows", 0), d.get("ListenDrops", 0)
    except Exception:
        return 0, 0

lo_before, ld_before = get_netstat()

# 3. Fire 30 concurrent connections
clients = []
success = 0
dropped = 0
for i in range(30):
    c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    c.settimeout(1.0)
    try:
        c.connect(('127.0.0.1', port))
        c.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
        clients.append(c)
        success += 1
    except Exception:
        dropped += 1
        try: c.close()
        except: pass

time.sleep(0.5)
lo_after, ld_after = get_netstat()

for c in clients:
    try: c.close()
    except: pass

if success < 30 or dropped > 0:
    print(f"Verification failed: Expected 30 successful connections, got {success} (dropped: {dropped}).")
    sys.exit(1)

overflow_delta = lo_after - lo_before
drop_delta = ld_after - ld_before
if overflow_delta > 0 or drop_delta > 0:
    print(f"Verification failed: ListenOverflows (+{overflow_delta}) or ListenDrops (+{drop_delta}) occurred during burst.")
    sys.exit(1)

# 4. Write verification marker
ts = str(int(time.time()))
raw = f"BACKLOG_VERIFIED:{pid}:{port}:{backlog}:{ts}".encode('utf-8')
token = hashlib.sha256(raw).hexdigest()

with open(MARKER_FILE, 'w') as f:
    f.write(f"VERIFICATION_STATUS=PASSED\nVERIFICATION_TOKEN={token}\nVERIFIED_PID={pid}\nPORT={port}\nBACKLOG={backlog}\nCONCURRENCY={concurrency}\n")

print("Verification PASSED: 30/30 burst connections succeeded with zero ListenOverflows/ListenDrops.")
sys.exit(0)
VERIFY_EOF
chmod 0755 "$INCIDENT_ROOT/bin/verify-backlog"

# 8. Start Service & Populate Saturated Accept Queue
"$INCIDENT_ROOT/bin/api-ctl" start >/dev/null 2>&1

# Seed 6 unaccepted connections to ensure ss -lnt shows Recv-Q: 6, Send-Q: 5
python3 -c "
import socket
import time
import os

port = $ASSIGNED_PORT
clients = []
for i in range(6):
    try:
        c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        c.connect(('127.0.0.1', port))
        clients.append(c)
    except:
        pass

# Fork a client holder process so connections remain established in Accept Queue
pid = os.fork()
if pid == 0:
    try:
        devnull = os.open(os.devnull, os.O_RDWR)
        os.dup2(devnull, 0)
        os.dup2(devnull, 1)
        os.dup2(devnull, 2)
        if devnull > 2:
            os.close(devnull)
    except:
        pass
    time.sleep(300)
    for c in clients:
        try: c.close()
        except: pass
    os._exit(0)
else:
    with open('$INCIDENT_ROOT/var/run/clients.pid', 'w') as f:
        f.write(str(pid) + '\n')
"
