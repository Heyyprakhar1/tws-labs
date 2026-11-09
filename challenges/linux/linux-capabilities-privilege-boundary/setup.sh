#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
mkdir -p "$TARGET_DIR/bin" "$TARGET_DIR/config" "$TARGET_DIR/system" "$TARGET_DIR/var/log" "$TARGET_DIR/reports"

# 1. Write initial legacy service configuration pointing to root-owned /var/run/app.pid
cat << EOF > "$TARGET_DIR/config/daemon.env"
# Legacy Microservice Configuration
SERVICE_PORT=8085
PID_FILE="/var/run/app.pid"
SOCKET_PATH="/var/run/app.sock"
LOG_FILE="$TARGET_DIR/var/log/app.log"
RUN_AS_USER="lab0"
EOF

# 2. Write educational systemd unit template
cat << EOF > "$TARGET_DIR/system/app-service.conf"
[Unit]
Description=Payment Transaction Gateway Service
After=network.target

[Service]
Type=simple
User=lab0
Group=lab0
NoNewPrivileges=true
CapabilityBoundingSet=
AmbientCapabilities=
EnvironmentFile=$TARGET_DIR/config/daemon.env
ExecStart=$TARGET_DIR/bin/service-daemon run
Restart=on-failure
EOF

# 3. Create bin/capability-decoder (Parses /proc/self/status and decodes 64-bit capability bitmask)
cat << 'EOF' > "$TARGET_DIR/bin/capability-decoder"
#!/usr/bin/env python3
import sys
import os

CAP_NAMES = [
    "cap_chown", "cap_dac_override", "cap_dac_read_search", "cap_fowner",
    "cap_fsetid", "cap_kill", "cap_setgid", "cap_setuid",
    "cap_setpcap", "cap_linux_immutable", "cap_net_bind_service", "cap_net_broadcast",
    "cap_net_admin", "cap_net_raw", "cap_ipc_lock", "cap_ipc_owner",
    "cap_sys_module", "cap_sys_rawio", "cap_sys_chroot", "cap_sys_ptrace",
    "cap_sys_pacct", "cap_sys_admin", "cap_sys_boot", "cap_sys_nice",
    "cap_sys_resource", "cap_sys_time", "cap_sys_tty_config", "cap_mknod",
    "cap_lease", "cap_audit_write", "cap_audit_control", "cap_setfcap",
    "cap_mac_override", "cap_mac_admin", "cap_syslog", "cap_wake_alarm",
    "cap_block_suspend", "cap_audit_read", "cap_perfmon", "cap_bpf",
    "cap_checkpoint_restore"
]

def decode_mask(hex_str):
    val = int(hex_str, 16)
    caps = []
    for i, name in enumerate(CAP_NAMES):
        if (val >> i) & 1:
            caps.append(name)
    return caps

def parse_status():
    caps = {}
    with open("/proc/self/status", "r") as f:
        for line in f:
            if line.startswith("Cap"):
                parts = line.strip().split(":")
                if len(parts) == 2:
                    caps[parts[0].strip()] = parts[1].strip()
    return caps

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].startswith("--mask="):
        mask = sys.argv[1].split("=")[1]
        decoded = decode_mask(mask)
        print(f"Mask 0x{mask}: {','.join(decoded) if decoded else 'None (Empty)'}")
    else:
        st = parse_status()
        print("=== Process Capabilities (/proc/self/status) ===")
        for k in ["CapInh", "CapPrm", "CapEff", "CapBnd", "CapAmb"]:
            m = st.get(k, "0000000000000000")
            dec = decode_mask(m)
            print(f"{k}: {m} ({len(dec)} active: {','.join(dec) if dec else 'empty'})")
EOF
chmod +x "$TARGET_DIR/bin/capability-decoder"

# 4. Create bin/service-daemon (Production-equivalent Python microservice)
cat << 'EOF' > "$TARGET_DIR/bin/service-daemon"
#!/usr/bin/env python3
import sys
import os
import signal
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

def load_config():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_dir = os.path.dirname(script_dir)
    conf_path = os.path.join(target_dir, "config", "daemon.env")
    cfg = {
        "SERVICE_PORT": 8085,
        "PID_FILE": "/var/run/app.pid",
        "LOG_FILE": os.path.join(target_dir, "var", "log", "app.log"),
    }
    if os.path.exists(conf_path):
        with open(conf_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip("\"'")
                    if k == "SERVICE_PORT":
                        cfg[k] = int(v)
                    elif k in ["PID_FILE", "LOG_FILE"]:
                        cfg[k] = os.path.expanduser(os.path.expandvars(v))
    return cfg, target_dir

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"healthy","user":"lab0","effective_capabilities":"0000000000000000"}\n')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass # Quiet server logs

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

def run_server(port, pid_file):
    def handle_term(signum, frame):
        try:
            if os.path.exists(pid_file):
                os.unlink(pid_file)
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_term)
    signal.signal(signal.SIGINT, handle_term)

    try:
        server = ReusableHTTPServer(("127.0.0.1", port), HealthHandler)
        server.serve_forever()
    except Exception:
        try:
            if os.path.exists(pid_file):
                os.unlink(pid_file)
        except Exception:
            pass
        sys.exit(1)

def cmd_start():
    cfg, target_dir = load_config()
    pid_file = cfg["PID_FILE"]
    port = cfg["SERVICE_PORT"]
    startup_log = os.path.join(target_dir, "var", "log", "service-startup.log")
    os.makedirs(os.path.dirname(startup_log), exist_ok=True)

    # If PID file already exists and daemon is alive, start is idempotent
    if os.path.exists(pid_file):
        try:
            with open(pid_file, "r") as f:
                existing_pid = int(f.read().strip())
            os.kill(existing_pid, 0)
            print(f"Service is already running (PID {existing_pid})")
            sys.exit(0)
        except (ValueError, OSError):
            pass

    # Check if directory exists or attempt to create PID file
    pid_dir = os.path.dirname(pid_file)
    try:
        if pid_dir and not os.path.exists(pid_dir):
            os.makedirs(pid_dir, exist_ok=True)
    except PermissionError as e:
        msg = f"PermissionError: [Errno 13] Permission denied: '{pid_dir}'"
        with open(startup_log, "w") as f:
            f.write(msg + "\n")
        print(f"Error starting service: {msg}", file=sys.stderr)
        sys.exit(1)

    try:
        # Attempt to write PID file
        test_f = open(pid_file, "w")
        test_f.close()
    except PermissionError as e:
        msg = f"PermissionError: [Errno 13] Permission denied: '{pid_file}'"
        with open(startup_log, "w") as f:
            f.write(msg + "\n")
        print(f"Error starting service: {msg}", file=sys.stderr)
        sys.exit(1)

    # Fork daemon
    pid = os.fork()
    if pid > 0:
        # Parent
        with open(pid_file, "w") as f:
            f.write(str(pid) + "\n")
        print(f"Service started in background (PID {pid}, port {port})")
        sys.exit(0)
    else:
        # Child: detach and redirect stdio so parent pipe closes cleanly
        os.setsid()
        sys.stdout.flush()
        sys.stderr.flush()
        devnull = os.open(os.devnull, os.O_RDWR)
        os.dup2(devnull, 0)
        os.dup2(devnull, 1)
        os.dup2(devnull, 2)
        os.close(devnull)
        run_server(port, pid_file)

def cmd_stop():
    cfg, _ = load_config()
    pid_file = cfg["PID_FILE"]
    if not os.path.exists(pid_file):
        print(f"No running service found (PID file {pid_file} does not exist)")
        sys.exit(0)
    try:
        with open(pid_file, "r") as f:
            pid = int(f.read().strip())
        try:
            os.kill(pid, signal.SIGTERM)
            for _ in range(20):
                try:
                    os.kill(pid, 0)
                    time.sleep(0.1)
                except OSError:
                    break
        except OSError:
            pass
        if os.path.exists(pid_file):
            os.unlink(pid_file)
        print(f"Service stopped (PID {pid})")
        sys.exit(0)
    except Exception as e:
        print(f"Error stopping service: {e}")
        sys.exit(1)

def cmd_status():
    cfg, _ = load_config()
    pid_file = cfg["PID_FILE"]
    if not os.path.exists(pid_file):
        print("Service is stopped")
        sys.exit(3)
    try:
        with open(pid_file, "r") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        print(f"Service is running (PID {pid})")
        sys.exit(0)
    except OSError:
        print(f"Service is dead but PID file {pid_file} exists")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: service-daemon {start|stop|status}")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "start":
        cmd_start()
    elif cmd == "stop":
        cmd_stop()
    elif cmd == "status":
        cmd_status()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
EOF
chmod +x "$TARGET_DIR/bin/service-daemon"

# 5. Create bin/verify-service (Verification runner)
cat << 'EOF' > "$TARGET_DIR/bin/verify-service"
#!/usr/bin/env python3
import sys
import os
import urllib.request
import json

def verify():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_dir = os.path.dirname(script_dir)
    conf_path = os.path.join(target_dir, "config", "daemon.env")

    print("=== Verifying Service Privilege Boundary ===")

    # 1. Check configuration
    if not os.path.exists(conf_path):
        print(f"FAILED: Configuration file {conf_path} missing")
        sys.exit(1)

    pid_file = None
    port = 8085
    with open(conf_path, "r") as f:
        for line in f:
            if line.startswith("PID_FILE="):
                pid_file = os.path.expanduser(os.path.expandvars(line.split("=", 1)[1].strip().strip("\"'")))
            elif line.startswith("SERVICE_PORT="):
                port = int(line.split("=", 1)[1].strip().strip("\"'"))

    if not pid_file or not pid_file.startswith(target_dir):
        print(f"FAILED: PID_FILE is configured at '{pid_file}'. It must point inside the user-owned workspace '{target_dir}'.")
        sys.exit(1)

    # 2. Check if PID file exists
    if not os.path.exists(pid_file):
        print(f"FAILED: PID file {pid_file} does not exist. Is the daemon running?")
        sys.exit(1)

    with open(pid_file, "r") as f:
        try:
            pid = int(f.read().strip())
        except ValueError:
            print("FAILED: PID file contains invalid PID")
            sys.exit(1)

    # 3. Check daemon process identity and capabilities via /proc/<pid>/status
    proc_status = f"/proc/{pid}/status"
    if not os.path.exists(proc_status):
        print(f"FAILED: Process {pid} is not running")
        sys.exit(1)

    uid = None
    gid = None
    capeff = None
    with open(proc_status, "r") as f:
        for line in f:
            if line.startswith("Uid:"):
                uid = line.split()[1]
            elif line.startswith("Gid:"):
                gid = line.split()[1]
            elif line.startswith("CapEff:"):
                capeff = line.split()[1]

    expected_uid = str(os.getuid())
    if uid != expected_uid:
        print(f"FAILED: Daemon is running as UID {uid}, expected learner UID {expected_uid}")
        sys.exit(1)

    if capeff != "0000000000000000":
        print(f"FAILED: Daemon has non-zero effective capabilities ({capeff}), expected 0000000000000000")
        sys.exit(1)

    # 4. Check HTTP Healthz
    try:
        req = urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=3)
        if req.status != 200:
            print(f"FAILED: Healthcheck returned HTTP {req.status}")
            sys.exit(1)
        resp = json.loads(req.read().decode())
        if resp.get("status") != "healthy":
            print(f"FAILED: Healthcheck payload status is '{resp.get('status')}'")
            sys.exit(1)
    except Exception as e:
        print(f"FAILED: Cannot reach service healthcheck on port {port}: {e}")
        sys.exit(1)

    print("=== Verification SUCCESS ===")
    print(f"Daemon (PID {pid}) verified:")
    print(f"  - Runtime directory: user-owned ({os.path.dirname(pid_file)})")
    print(f"  - UID: {uid} (non-root learner)")
    print(f"  - Effective Capabilities: {capeff} (zero elevated capabilities)")
    print(f"  - Health Endpoint: HTTP 200 OK")
    sys.exit(0)

if __name__ == "__main__":
    verify()
EOF
chmod +x "$TARGET_DIR/bin/verify-service"
