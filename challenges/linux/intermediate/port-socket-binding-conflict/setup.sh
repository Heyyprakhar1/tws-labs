#!/bin/bash
set -euo pipefail

BASE="$HOME/port-incident"
rm -rf "$BASE"
mkdir -p "$BASE/bin" "$BASE/config" "$BASE/logs" "$BASE/reports" "$BASE/var/run"

# 1. Configurable single source of truth for ports
if [ -n "${PORT_HTTP:-}" ]; then
  PORT_HTTP="$PORT_HTTP"
elif [ -n "${LAB_UID:-}" ]; then
  PORT_HTTP=$((18080 + (LAB_UID % 1000)))
else
  PORT_HTTP=18080
fi

if [ -n "${PORT_METRICS:-}" ]; then
  PORT_METRICS="$PORT_METRICS"
elif [ -n "${LAB_UID:-}" ]; then
  PORT_METRICS=$((19090 + (LAB_UID % 1000)))
else
  PORT_METRICS=19090
fi

cat << EOF > "$BASE/config/ports.env"
PORT_HTTP=$PORT_HTTP
PORT_METRICS=$PORT_METRICS
EOF
chmod 0644 "$BASE/config/ports.env"

# 2. Defective proxy configuration (metrics bound to localhost only)
cat << 'EOF' > "$BASE/config/proxy.env"
# Authentication Proxy Interface Configuration
PROXY_NAME=auth-proxy
PROXY_BIND=0.0.0.0
METRICS_BIND=127.0.0.1
LOG_LEVEL=info
EOF
chmod 0644 "$BASE/config/proxy.env"

# 3. Provision rogue-listener executable (holds PORT_HTTP)
cat << 'ROGUE_EOF' > "$BASE/bin/rogue-listener"
#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');

const portsFile = path.join(__dirname, '..', 'config', 'ports.env');
let port = 18080;
if (fs.existsSync(portsFile)) {
  const content = fs.readFileSync(portsFile, 'utf8');
  const m = content.match(/PORT_HTTP=(\d+)/);
  if (m) port = parseInt(m[1], 10);
}

const pidFile = path.join(__dirname, '..', 'var', 'run', 'rogue-listener.pid');
const refFile = path.join(__dirname, '..', 'var', 'run', '.rogue-listener.ref');
const identityFile = path.join(__dirname, '..', 'var', 'run', '.rogue-listener.identity');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('rogue-listener active\n');
});

server.on('error', (err) => {
  console.error('[rogue-listener error]', err.message);
  process.exit(1);
});

server.listen(port, '0.0.0.0', () => {
  // Extract starttime (field 22) from /proc/self/stat
  let starttime = '';
  if (process.env.TEST_MOCK_STAT_ERROR !== '1') {
    try {
      const statContent = fs.readFileSync('/proc/self/stat', 'utf8');
      const afterComm = statContent.slice(statContent.lastIndexOf(')') + 2).trim().split(/\s+/);
      if (afterComm.length > 19 && /^\d+$/.test(afterComm[19])) {
        starttime = afterComm[19];
      }
    } catch {}
  }

  if (!starttime) {
    console.error('[rogue-listener error] Failed to acquire valid start time from /proc/self/stat');
    server.close(() => process.exit(1));
    return;
  }

  const identityContent = `PID=${process.pid}\nSTARTTIME=${starttime}\nPORT=${port}\nCOMMAND=rogue-listener\n`;
  try {
    if (process.env.TEST_MOCK_IDENTITY_WRITE_ERROR === '1') {
      throw new Error('Simulated identity write failure');
    }
    fs.writeFileSync(identityFile, identityContent, { mode: 0o600 });
  } catch (err) {
    console.error('[rogue-listener error] Failed to write identity record:', err.message);
    try { if (fs.existsSync(identityFile)) fs.unlinkSync(identityFile); } catch {}
    try { if (fs.existsSync(pidFile)) fs.unlinkSync(pidFile); } catch {}
    try { if (fs.existsSync(refFile)) fs.unlinkSync(refFile); } catch {}
    server.close(() => process.exit(1));
    return;
  }

  try {
    fs.writeFileSync(pidFile, String(process.pid), { mode: 0o644 });
    fs.writeFileSync(refFile, String(process.pid), { mode: 0o600 });
  } catch (err) {
    console.error('[rogue-listener error] Failed to write PID/reference files:', err.message);
    try { if (fs.existsSync(identityFile)) fs.unlinkSync(identityFile); } catch {}
    try { if (fs.existsSync(pidFile)) fs.unlinkSync(pidFile); } catch {}
    try { if (fs.existsSync(refFile)) fs.unlinkSync(refFile); } catch {}
    server.close(() => process.exit(1));
    return;
  }
});

function cleanup() {
  server.close(() => {
    process.exit(0);
  });
}

if (process.env.TEST_IGNORE_SIGTERM === '1') {
  process.on('SIGTERM', () => {
    // Test hook: deliberately ignore SIGTERM to test SIGKILL fallback
  });
} else {
  process.on('SIGTERM', cleanup);
}
process.on('SIGINT', cleanup);
ROGUE_EOF
chmod 0755 "$BASE/bin/rogue-listener"

# 4. Spawn rogue-listener with detached/decoupled stdio under session UID
(exec node "$BASE/bin/rogue-listener" </dev/null >> "$BASE/logs/rogue-listener.log" 2>&1 &)

# Wait up to 2 seconds for listener to bind and write identity
for i in {1..20}; do
  if [ -f "$BASE/var/run/.rogue-listener.identity" ] && [ -f "$BASE/var/run/rogue-listener.pid" ]; then
    break
  fi
  sleep 0.1
done
chmod 0600 "$BASE/var/run/.rogue-listener.identity" 2>/dev/null || true
if [ ! -f "$BASE/var/run/.rogue-listener.identity" ]; then
  echo "Error: rogue-listener failed to start and bind port $PORT_HTTP" >&2
  if [ -f "$BASE/logs/rogue-listener.log" ]; then
    cat "$BASE/logs/rogue-listener.log" >&2
  fi
  exit 1
fi

# Verify that setup validates identity record's PID, start time and configured port before declaring success
ID_PID=$(grep -E '^[[:space:]]*PID=' "$BASE/var/run/.rogue-listener.identity" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
ID_STARTTIME=$(grep -E '^[[:space:]]*STARTTIME=' "$BASE/var/run/.rogue-listener.identity" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
ID_PORT=$(grep -E '^[[:space:]]*PORT=' "$BASE/var/run/.rogue-listener.identity" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
ID_COMMAND=$(grep -E '^[[:space:]]*COMMAND=' "$BASE/var/run/.rogue-listener.identity" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')

if [ -z "$ID_PID" ] || [ -z "$ID_STARTTIME" ] || [ -z "$ID_PORT" ] || [ -z "$ID_COMMAND" ]; then
  echo "Error: rogue-listener identity file missing required fields." >&2
  exit 1
fi

if ! [[ "$ID_PID" =~ ^[0-9]+$ ]] || ! [[ "$ID_STARTTIME" =~ ^[0-9]+$ ]] || [ "$ID_PORT" != "$PORT_HTTP" ] || [ "$ID_COMMAND" != "rogue-listener" ]; then
  echo "Error: rogue-listener identity record is invalid or port mismatch." >&2
  exit 1
fi

# 5. Provision auth-proxy daemon executable
cat << 'DAEMON_EOF' > "$BASE/bin/auth-proxy-daemon"
#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');

const baseDir = path.join(__dirname, '..');
const portsFile = path.join(baseDir, 'config', 'ports.env');
const proxyFile = path.join(baseDir, 'config', 'proxy.env');
const logFile = path.join(baseDir, 'logs', 'proxy.log');
const pidFile = path.join(baseDir, 'var', 'run', 'auth-proxy.pid');

let portHttp = 18080;
let portMetrics = 19090;
let proxyBind = '0.0.0.0';
let metricsBind = '127.0.0.1';

if (fs.existsSync(portsFile)) {
  const c = fs.readFileSync(portsFile, 'utf8');
  const mH = c.match(/PORT_HTTP=(\d+)/);
  const mM = c.match(/PORT_METRICS=(\d+)/);
  if (mH) portHttp = parseInt(mH[1], 10);
  if (mM) portMetrics = parseInt(mM[1], 10);
}

if (fs.existsSync(proxyFile)) {
  const c = fs.readFileSync(proxyFile, 'utf8');
  const mP = c.match(/PROXY_BIND=([^\s\n]+)/);
  const mM = c.match(/METRICS_BIND=([^\s\n]+)/);
  if (mP) proxyBind = mP[1].trim();
  if (mM) metricsBind = mM[1].trim();
}

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  fs.appendFileSync(logFile, line);
}

const proxyServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('auth-proxy: ok\n');
});

const metricsServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('# HELP auth_proxy_requests_total Total HTTP requests\nauth_proxy_requests_total 42\n');
});

let proxyStarted = false;
let metricsStarted = false;

proxyServer.on('error', (err) => {
  log(`[FATAL] listen EADDRINUSE: address already in use ${proxyBind}:${portHttp}`);
  console.error(`[FATAL] listen EADDRINUSE: address already in use ${proxyBind}:${portHttp}`);
  try { metricsServer.close(); } catch {}
  process.exit(1);
});

metricsServer.on('error', (err) => {
  log(`[FATAL] metrics listen error on ${metricsBind}:${portMetrics}: ${err.message}`);
  console.error(`[FATAL] metrics listen error: ${err.message}`);
  try { proxyServer.close(); } catch {}
  process.exit(1);
});

proxyServer.listen(portHttp, proxyBind, () => {
  proxyStarted = true;
  log(`[INFO] auth-proxy listening on ${proxyBind}:${portHttp}`);
  if (metricsStarted) onAllStarted();
});

metricsServer.listen(portMetrics, metricsBind, () => {
  metricsStarted = true;
  log(`[INFO] metrics exporter listening on ${metricsBind}:${portMetrics}`);
  if (proxyStarted) onAllStarted();
});

function onAllStarted() {
  fs.writeFileSync(pidFile, String(process.pid));
  log(`[INFO] auth-proxy started (PID ${process.pid})`);
}

function shutdown() {
  try { proxyServer.close(); } catch {}
  try { metricsServer.close(); } catch {}
  try { fs.unlinkSync(pidFile); } catch {}
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
DAEMON_EOF
chmod 0755 "$BASE/bin/auth-proxy-daemon"

# 6. Provision auth-proxy launcher CLI
cat << 'LAUNCHER_EOF' > "$BASE/bin/auth-proxy"
#!/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--start" ]; then
  PID_FILE="$BASE_DIR/var/run/auth-proxy.pid"
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "auth-proxy already running (PID $OLD_PID)"
      exit 0
    fi
  fi
  (exec node "$BASE_DIR/bin/auth-proxy-daemon" </dev/null >> "$BASE_DIR/logs/proxy.log" 2>&1 &)
  for i in {1..15}; do
    if [ -f "$PID_FILE" ]; then
      echo "Started auth-proxy (PID $(cat "$PID_FILE"))"
      exit 0
    fi
    sleep 0.1
  done
  echo "Error: auth-proxy failed to start. Check $BASE_DIR/logs/proxy.log" >&2
  exit 1
else
  echo "Usage: ./bin/auth-proxy --start"
  exit 1
fi
LAUNCHER_EOF
chmod 0755 "$BASE/bin/auth-proxy"

# 7. Provision socket-tool helper
cat << 'TOOL_EOF' > "$BASE/bin/socket-tool"
#!/bin/bash
set -euo pipefail
if command -v ss >/dev/null 2>&1; then
  exec ss -tlpn
elif command -v netstat >/dev/null 2>&1; then
  exec netstat -tlpn
else
  exec lsof -i -P -n
fi
TOOL_EOF
chmod 0755 "$BASE/bin/socket-tool"

# 8. Provision challenge-owned kill-listener helper with session validation
cat << 'KILL_EOF' > "$BASE/bin/kill-listener"
#!/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$BASE_DIR/var/run/rogue-listener.pid"
IDENTITY_FILE="$BASE_DIR/var/run/.rogue-listener.identity"

TARGET_PID="${1:-}"

# 1. Require setup-recorded identity file
if [ ! -f "$IDENTITY_FILE" ]; then
  echo "Error: Identity file $IDENTITY_FILE missing. Cannot authenticate rogue-listener." >&2
  exit 1
fi

RECORDED_PID=$(grep -E '^[[:space:]]*PID=' "$IDENTITY_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
RECORDED_STARTTIME=$(grep -E '^[[:space:]]*STARTTIME=' "$IDENTITY_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
RECORDED_PORT=$(grep -E '^[[:space:]]*PORT=' "$IDENTITY_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')
RECORDED_COMMAND=$(grep -E '^[[:space:]]*COMMAND=' "$IDENTITY_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]"')

if [ -z "$RECORDED_PID" ] || [ -z "$RECORDED_STARTTIME" ] || [ -z "$RECORDED_PORT" ]; then
  echo "Error: Invalid setup identity in $IDENTITY_FILE." >&2
  exit 1
fi

# Reject any learner-supplied PID that does not match the setup-recorded PID
if [ -n "$TARGET_PID" ] && [ "$TARGET_PID" != "$RECORDED_PID" ]; then
  echo "Error: Supplied PID $TARGET_PID does not match recorded session rogue-listener PID ($RECORDED_PID)." >&2
  exit 1
fi

TARGET_PID="$RECORDED_PID"

# Helper to extract starttime (field 22) from /proc/<pid>/stat
get_starttime() {
  local p="$1"
  if [ -r "/proc/$p/stat" ]; then
    local stat_line
    stat_line=$(cat "/proc/$p/stat" 2>/dev/null || true)
    local after="${stat_line##*)} "
    local fields=()
    read -r -a fields <<< "$after"
    echo "${fields[19]:-}"
  fi
}

# Helper to verify socket ownership on RECORDED_PORT
check_socket_ownership() {
  local p="$1"
  local port="$2"

  # A. Check /proc/net/tcp and /proc/net/tcp6 via /proc/<pid>/fd
  local hex_port
  hex_port=$(printf "%04X" "$port")

  local inodes=""
  if [ -r /proc/net/tcp ]; then
    inodes=$(awk -v hp=":$hex_port" '$2 ~ hp && $4 == "0A" { print $10 }' /proc/net/tcp 2>/dev/null || true)
  fi
  if [ -z "$inodes" ] && [ -r /proc/net/tcp6 ]; then
    inodes=$(awk -v hp=":$hex_port" '$2 ~ hp && $4 == "0A" { print $10 }' /proc/net/tcp6 2>/dev/null || true)
  fi

  if [ -n "$inodes" ] && [ -d "/proc/$p/fd" ]; then
    for fd_link in "/proc/$p/fd"/*; do
      if [ -L "$fd_link" ]; then
        local target
        target=$(readlink "$fd_link" 2>/dev/null || true)
        for inode in $inodes; do
          if [ "$target" = "socket:[$inode]" ]; then
            return 0
          fi
        done
      fi
    done
  fi

  # B. Check ss if available
  if command -v ss >/dev/null 2>&1; then
    local ss_out
    ss_out=$(ss -tlpn "sport = :$port" 2>/dev/null || ss -tlpn 2>/dev/null || true)
    if echo "$ss_out" | grep -q "pid=$p," || echo "$ss_out" | grep -q "pid=$p)"; then
      return 0
    fi
  fi

  return 1
}

# Validate full target identity
# Returns:
#   0: valid target
#   1: invalid target / mismatch / security rejection
#   2: process already exited
validate_target() {
  local p="$1"

  # 1. Existence
  if [ ! -d "/proc/$p" ]; then
    return 2
  fi

  # 2. Session UID ownership
  local owner_uid
  owner_uid=$(stat -c %u "/proc/$p" 2>/dev/null || true)
  if [ "$owner_uid" != "$UID" ]; then
    echo "Error: Process $p is not owned by current session user ($UID)." >&2
    return 1
  fi

  # 3. Command identity
  local cmdline
  cmdline=$(cat "/proc/$p/cmdline" 2>/dev/null | tr '\0' ' ' || true)
  local expected_cmd="${RECORDED_COMMAND:-rogue-listener}"
  if ! echo "$cmdline" | grep -q "$expected_cmd"; then
    echo "Error: Process $p is not $expected_cmd." >&2
    return 1
  fi

  # 4. Process start time from /proc/<pid>/stat
  local current_starttime
  current_starttime=$(get_starttime "$p")
  if [ -n "$RECORDED_STARTTIME" ] && [ "$current_starttime" != "$RECORDED_STARTTIME" ]; then
    echo "Error: Process $p start time mismatch ($current_starttime != $RECORDED_STARTTIME). Possible PID reuse." >&2
    return 1
  fi

  # 5. Socket ownership on configured HTTP port
  if ! check_socket_ownership "$p" "$RECORDED_PORT"; then
    echo "Error: Process $p does not own listening socket on port $RECORDED_PORT." >&2
    return 1
  fi

  return 0
}

# Initial validation before SIGTERM
set +e
validate_target "$TARGET_PID"
V_STATUS=$?
set -e

if [ "$V_STATUS" -eq 2 ]; then
  # Already exited
  echo "Process $TARGET_PID is not running."
  exit 0
elif [ "$V_STATUS" -ne 0 ]; then
  exit 1
fi

# Send SIGTERM
kill -TERM "$TARGET_PID" 2>/dev/null || true

# Wait loop detecting process exit or identity changes
for i in {1..15}; do
  if [ ! -d "/proc/$TARGET_PID" ]; then
    break
  fi

  # If still present, detect identity change (PID recycled)
  curr_uid=$(stat -c %u "/proc/$TARGET_PID" 2>/dev/null || true)
  curr_st=$(get_starttime "$TARGET_PID")
  if [ -d "/proc/$TARGET_PID" ] && { [ "$curr_uid" != "$UID" ] || [ "$curr_st" != "$RECORDED_STARTTIME" ]; }; then
    break
  fi

  sleep 0.1
done

# Fallback SIGKILL with full re-validation
if [ -d "/proc/$TARGET_PID" ]; then
  # Test hook: simulate target identity change between SIGTERM and SIGKILL
  if [ "${TEST_HOOK_CORRUPT_IDENTITY_BEFORE_KILL:-}" = "1" ]; then
    RECORDED_STARTTIME="999999999"
  fi

  set +e
  validate_target "$TARGET_PID"
  KILL_VALID=$?
  set -e

  if [ "$KILL_VALID" -eq 0 ]; then
    kill -KILL "$TARGET_PID" 2>/dev/null || true
    for j in {1..10}; do
      if [ ! -d "/proc/$TARGET_PID" ]; then
        break
      fi
      sleep 0.05
    done
  elif [ "$KILL_VALID" -eq 2 ]; then
    :
  else
    echo "Error: Process $TARGET_PID identity changed before SIGKILL. Fallback aborted." >&2
    exit 1
  fi
fi

if [ -d "/proc/$TARGET_PID" ]; then
  echo "Error: Failed to terminate process $TARGET_PID." >&2
  exit 1
fi

echo "Terminated rogue-listener (PID $TARGET_PID)."
exit 0
KILL_EOF
chmod 0755 "$BASE/bin/kill-listener"

# 9. Provision verify-sockets audit runner
cat << 'VERIFY_EOF' > "$BASE/bin/verify-sockets"
#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');

const baseDir = path.join(__dirname, '..');
const portsFile = path.join(baseDir, 'config', 'ports.env');
const proxyFile = path.join(baseDir, 'config', 'proxy.env');
const pidFile = path.join(baseDir, 'var', 'run', 'auth-proxy.pid');
const roguePidFile = path.join(baseDir, 'var', 'run', 'rogue-listener.pid');
const markerFile = path.join(baseDir, '.socket-audit.passed');

let portHttp = 18080;
let portMetrics = 19090;

if (fs.existsSync(portsFile)) {
  const c = fs.readFileSync(portsFile, 'utf8');
  const mH = c.match(/PORT_HTTP=(\d+)/);
  const mM = c.match(/PORT_METRICS=(\d+)/);
  if (mH) portHttp = parseInt(mH[1], 10);
  if (mM) portMetrics = parseInt(mM[1], 10);
}

// 1. Verify rogue-listener is dead
if (fs.existsSync(roguePidFile)) {
  try {
    const roguePid = parseInt(fs.readFileSync(roguePidFile, 'utf8').trim(), 10);
    process.kill(roguePid, 0);
    console.error('FAIL: rogue-listener process is still active.');
    process.exit(1);
  } catch (err) {
    // Process is dead as expected
  }
}

// 2. Verify proxy.env has wildcard bindings
if (!fs.existsSync(proxyFile)) {
  console.error('FAIL: config/proxy.env is missing.');
  process.exit(1);
}
const proxyConf = fs.readFileSync(proxyFile, 'utf8');
if (!proxyConf.includes('PROXY_BIND=0.0.0.0')) {
  console.error('FAIL: PROXY_BIND is not 0.0.0.0.');
  process.exit(1);
}
if (!proxyConf.includes('METRICS_BIND=0.0.0.0')) {
  console.error('FAIL: METRICS_BIND is not 0.0.0.0 (must accept all interfaces).');
  process.exit(1);
}

// 3. Verify auth-proxy PID is active
if (!fs.existsSync(pidFile)) {
  console.error('FAIL: auth-proxy is not running (PID file missing). Start it with ./bin/auth-proxy --start');
  process.exit(1);
}
const proxyPid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
try {
  process.kill(proxyPid, 0);
} catch {
  console.error('FAIL: auth-proxy PID is not active.');
  process.exit(1);
}

// 4. Test HTTP endpoints
function testGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject);
  });
}

(async () => {
  try {
    const resHttp = await testGet(`http://127.0.0.1:${portHttp}/`);
    if (resHttp.status !== 200 || !resHttp.body.includes('auth-proxy: ok')) {
      console.error(`FAIL: auth-proxy on port ${portHttp} returned unexpected response: ${resHttp.body}`);
      process.exit(1);
    }

    const resMetrics = await testGet(`http://127.0.0.1:${portMetrics}/`);
    if (resMetrics.status !== 200 || !resMetrics.body.includes('auth_proxy_requests_total')) {
      console.error(`FAIL: metrics exporter on port ${portMetrics} returned unexpected response: ${resMetrics.body}`);
      process.exit(1);
    }

    fs.writeFileSync(markerFile, JSON.stringify({
      status: 'PASSED',
      audit: 'port-socket-binding-conflict',
      port_http: portHttp,
      port_metrics: portMetrics,
      timestamp: new Date().toISOString()
    }));
    console.log(`SUCCESS: Port conflict resolved and sockets verified on ${portHttp} and ${portMetrics}.`);
    process.exit(0);
  } catch (err) {
    console.error('FAIL: HTTP connection test failed:', err.message);
    process.exit(1);
  }
})();
VERIFY_EOF
chmod 0755 "$BASE/bin/verify-sockets"

# 10. Clear marker
rm -f "$BASE/.socket-audit.passed"
