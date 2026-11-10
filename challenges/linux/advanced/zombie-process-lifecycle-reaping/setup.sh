#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
mkdir -p "$INCIDENT_DIR"/{bin,config,reports,logs,var/run}

# 1. Generate config/supervisor.env
cat > "$INCIDENT_DIR/config/supervisor.env" <<'EOF'
# Batch Supervisor Runtime Configuration
MAX_WORKERS=10
ENABLE_SIGCHLD_REAPER=false
EOF

# 2. Create bin/batch-worker
cat > "$INCIDENT_DIR/bin/batch-worker" <<'PYEOF'
#!/usr/bin/env python3
import time
import sys

# Perform short unit of synthetic work and terminate
time.sleep(0.05)
sys.exit(0)
PYEOF
chmod +x "$INCIDENT_DIR/bin/batch-worker"

# 3. Create bin/batch-supervisor
cat > "$INCIDENT_DIR/bin/batch-supervisor" <<'PYEOF'
#!/usr/bin/env python3
"""
Telemetry Batch Supervisor Daemon.
Demonstrates Linux process lifecycle, defunct zombies, and asynchronous SIGCHLD reaping.
"""
import os
import sys
import time
import signal
import subprocess

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(INCIDENT_DIR, "config", "supervisor.env")
LOG_FILE = os.path.join(INCIDENT_DIR, "logs", "supervisor.log")
PID_FILE = os.path.join(INCIDENT_DIR, "var", "run", "supervisor.pid")
WORKER_BIN = os.path.join(INCIDENT_DIR, "bin", "batch-worker")

reaped_pids = set()
spawned_pids = []
running = True

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime())
    line = f"[{ts}] {msg}\n"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception:
        pass

def is_reaper_enabled():
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE) as f:
                for line in f:
                    if line.strip().startswith("ENABLE_SIGCHLD_REAPER="):
                        val = line.strip().split("=", 1)[1].strip().lower()
                        return val in ["true", "yes", "1"]
        except Exception:
            pass
    return False

def sigchld_handler(signum, frame):
    """
    Standard non-blocking SIGCHLD reaper loop.
    Repeatedly calls waitpid(-1, WNOHANG) until all terminated children are reaped.
    """
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
            if pid <= 0:
                break
            reaped_pids.add(pid)
            log(f"SIGCHLD: Reaped child PID {pid} (exit status: {os.waitstatus_to_exitcode(status) if hasattr(os, 'waitstatus_to_exitcode') else (status >> 8)})")
        except (ChildProcessError, OSError):
            break

def sigusr1_handler(signum, frame):
    """Trigger dispatch of a new batch of 10 workers."""
    log("Received SIGUSR1: Dispatching new worker batch...")
    spawn_workers(10)

def sigterm_handler(signum, frame):
    global running
    log("Received SIGTERM: Shutting down supervisor daemon...")
    running = False
    # Drain any remaining children on shutdown
    while True:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
            if pid <= 0: break
        except (ChildProcessError, OSError):
            break
    sys.exit(0)

def spawn_workers(count=10):
    global spawned_pids
    log(f"Spawning {count} batch-worker child processes...")
    for i in range(count):
        try:
            # Fork child worker directly
            pid = os.fork()
            if pid == 0:
                # In child process: execute worker
                try:
                    os.execv(sys.executable, [sys.executable, WORKER_BIN])
                except Exception:
                    os._exit(1)
            else:
                # In parent: record child PID
                spawned_pids.append(pid)
        except OSError as e:
            log(f"Fork failed: {e}")

def main():
    signal.signal(signal.SIGTERM, sigterm_handler)
    signal.signal(signal.SIGINT, sigterm_handler)
    signal.signal(signal.SIGUSR1, sigusr1_handler)

    reaper_active = is_reaper_enabled()
    if reaper_active:
        log("SIGCHLD reaper enabled. Installing non-blocking waitpid handler.")
        signal.signal(signal.SIGCHLD, sigchld_handler)
    else:
        log("WARNING: SIGCHLD reaper is DISABLED. Terminated children will remain as zombies.")
        # Do not handle SIGCHLD: child processes will remain in state Z

    # Write supervisor PID
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()) + "\n")

    # Initial batch spawn of 10 workers
    spawn_workers(10)

    # Supervisor main loop
    while running:
        time.sleep(0.5)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INCIDENT_DIR/bin/batch-supervisor"

# 4. Create bin/supervisor-ctl
cat > "$INCIDENT_DIR/bin/supervisor-ctl" <<'SH_EOF'
#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$INCIDENT_DIR/var/run/supervisor.pid"
LOG_FILE="$INCIDENT_DIR/logs/supervisor.log"

count_zombies() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        ps -o pid,ppid,stat,cmd -u "$UID" 2>/dev/null | awk -v ppid="$PID" '$2 == ppid && $3 ~ /Z/ { count++ } END { print count+0 }'
    else
        echo "0"
    fi
}

case "${1:-}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "batch-supervisor is already running (PID $(cat "$PID_FILE"))."
            exit 0
        fi
        nohup python3 "$INCIDENT_DIR/bin/batch-supervisor" >/dev/null 2>&1 &
        sleep 0.3
        if [ -f "$PID_FILE" ]; then
            echo "Started batch-supervisor (PID $(cat "$PID_FILE"))."
        else
            echo "Failed to start batch-supervisor."
            exit 1
        fi
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID" 2>/dev/null || true
                for _ in {1..20}; do
                    if ! kill -0 "$PID" 2>/dev/null; then break; fi
                    sleep 0.1
                done
                kill -9 "$PID" 2>/dev/null || true
            fi
            rm -f "$PID_FILE"
            echo "Stopped batch-supervisor."
        else
            echo "batch-supervisor is not running."
        fi
        ;;
    restart)
        "$0" stop || true
        "$0" start
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            Z_COUNT=$(count_zombies)
            echo "batch-supervisor is running (PID $(cat "$PID_FILE"), active zombies: $Z_COUNT)."
        else
            echo "batch-supervisor is stopped."
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
SH_EOF
chmod +x "$INCIDENT_DIR/bin/supervisor-ctl"

# 5. Create bin/verify-reaping
cat > "$INCIDENT_DIR/bin/verify-reaping" <<'PYEOF'
#!/usr/bin/env python3
"""
Worker Lifecycle & Zombie Reaping Verification Tool.
Spawns a batch of workers, tests SIGCHLD reaping, and inspects the Linux process table.
"""
import os
import sys
import time
import signal
import subprocess

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(INCIDENT_DIR, "config", "supervisor.env")
PID_FILE = os.path.join(INCIDENT_DIR, "var", "run", "supervisor.pid")
REPORT_FILE = os.path.join(INCIDENT_DIR, "reports", "recovery-report.env")

def get_supervisor_pid():
    if os.path.exists(PID_FILE):
        try:
            with open(PID_FILE) as f:
                pid = int(f.read().strip())
                os.kill(pid, 0)
                return pid
        except Exception:
            pass
    return None

def is_reaper_enabled():
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.strip().startswith("ENABLE_SIGCHLD_REAPER="):
                    val = line.strip().split("=", 1)[1].strip().lower()
                    return val in ["true", "yes", "1"]
    return False

def count_zombies(ppid):
    count = 0
    cmd = ["ps", "-o", "pid,ppid,stat,cmd", "-u", str(os.getuid())]
    res = subprocess.run(cmd, capture_output=True, text=True)
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            p_pid, p_ppid, stat = parts[0], parts[1], parts[2]
            if p_ppid == str(ppid) and "Z" in stat:
                count += 1
    return count

def main():
    print("[*] Inspecting supervisor daemon and process table...")
    pid = get_supervisor_pid()
    if not pid:
        print("[FAIL] batch-supervisor daemon is not running. Start with ./bin/supervisor-ctl start.")
        sys.exit(1)

    reaper_active = is_reaper_enabled()
    initial_zombies = count_zombies(pid)
    print(f"    Supervisor PID:          {pid}")
    print(f"    SIGCHLD Reaper Enabled:  {reaper_active}")
    print(f"    Current Active Zombies:  {initial_zombies}")

    if not reaper_active or initial_zombies > 0:
        print(f"\n[FAIL] Defunct processes detected ({initial_zombies} zombies).")
        print("       The supervisor is not reaping terminated children.")
        print("       Enable ENABLE_SIGCHLD_REAPER=true in config/supervisor.env and restart.")
        sys.exit(1)

    # Dispatch a new test batch of 10 workers via SIGUSR1
    print("\n[*] Dispatching test batch of 10 workers via SIGUSR1...")
    os.kill(pid, signal.SIGUSR1)
    time.sleep(0.6)  # Allow workers to complete and reaper to handle SIGCHLD

    post_zombies = count_zombies(pid)
    print(f"    Lingering Zombies after batch: {post_zombies}")

    if post_zombies == 0:
        print("\n[PASS] All 10 replacement workers completed and were cleanly reaped via SIGCHLD.")
        os.makedirs(os.path.dirname(REPORT_FILE), exist_ok=True)
        with open(REPORT_FILE, "w") as f:
            f.write("VERIFICATION_STATUS=SUCCESS\n")
            f.write("WORKERS_DISPATCHED=10\n")
            f.write("WORKERS_REAPED=10\n")
            f.write("ACTIVE_ZOMBIES=0\n")
            f.write("REAPER_ACTIVE=true\n")
        print("       Recovery report written to reports/recovery-report.env.")
        sys.exit(0)
    else:
        print(f"\n[FAIL] {post_zombies} lingering zombie processes detected after test batch.")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INCIDENT_DIR/bin/verify-reaping"

# 6. Start supervisor to seed initial 10 zombies
"$INCIDENT_DIR/bin/supervisor-ctl" start
sleep 0.5
