#!/bin/bash
set -euo pipefail

BASE="$HOME/fd-incident"
rm -rf "$BASE"
mkdir -p "$BASE/bin" "$BASE/config" "$BASE/systemd/system" "$BASE/logs" "$BASE/reports" "$BASE/tmp/chunks" "$BASE/var/run"

# 1. Defective worker configuration (AUTO_CLOSE_CHUNKS=false)
cat << 'EOF' > "$BASE/config/worker.env"
# Event Collector Ingestion Worker Configuration
SERVICE_NAME=event-collector
AUTO_CLOSE_CHUNKS=false
CHUNK_STAGING_DIR=tmp/chunks
LOG_LEVEL=info
EOF
chmod 0644 "$BASE/config/worker.env"

# 2. Defective systemd unit file (LimitNOFILE=256)
cat << 'EOF' > "$BASE/systemd/system/event-collector.service"
[Unit]
Description=Event Collector Batch Ingestion Service
After=network.target

[Service]
Type=simple
ExecStart=bin/worker-daemon
Restart=on-failure
LimitNOFILE=256

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$BASE/systemd/system/event-collector.service"

# 3. Provision worker daemon
cat << 'WORKER_EOF' > "$BASE/bin/worker-daemon"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const http = require('http');

const baseDir = path.resolve(__dirname, '..');
const configPath = path.join(baseDir, 'config', 'worker.env');
const pidFile = path.join(baseDir, 'var', 'run', 'event-collector.pid');
const sockPath = path.join(baseDir, 'var', 'run', 'worker.sock');
const logFile = path.join(baseDir, 'logs', 'worker.log');
const chunksDir = path.join(baseDir, 'tmp', 'chunks');
const readyFile = path.join(baseDir, 'var', 'run', '.ready');

fs.mkdirSync(path.dirname(pidFile), { recursive: true });
fs.mkdirSync(path.dirname(logFile), { recursive: true });
fs.mkdirSync(chunksDir, { recursive: true });

// Pre-open log and ready descriptors so writes cannot fail during EMFILE saturation
const logFd = fs.openSync(logFile, 'a');
function log(msg) {
  try {
    fs.writeSync(logFd, `[${new Date().toISOString()}] ${msg}\n`);
  } catch {}
}

const readyFd = fs.openSync(readyFile, 'w');

let autoCloseChunks = false;
try {
  if (fs.existsSync(configPath)) {
    const c = fs.readFileSync(configPath, 'utf8');
    if (/^AUTO_CLOSE_CHUNKS\s*=\s*true/m.test(c)) {
      autoCloseChunks = true;
    }
  }
} catch (e) {
  log(`Error reading config: ${e.message}`);
}

fs.writeFileSync(pidFile, String(process.pid));
log(`worker-daemon started (PID ${process.pid}, AUTO_CLOSE_CHUNKS=${autoCloseChunks})`);

const openChunkFds = [];

try { fs.unlinkSync(sockPath); } catch {}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/ingest-batch') {
    const count = parseInt(url.searchParams.get('count') || '50', 10);
    let created = 0;
    let errorOccurred = null;

    for (let i = 0; i < count; i++) {
      const p = path.join(chunksDir, `chunk-${process.pid}-${Date.now()}-${i}.tmp`);
      try {
        const fd = fs.openSync(p, 'w');
        fs.writeSync(fd, `batch-data-${i}\n`);
        fs.unlinkSync(p); // Unlink so handle becomes (deleted) in /proc/<PID>/fd
        if (autoCloseChunks) {
          fs.closeSync(fd);
        } else {
          openChunkFds.push(fd);
        }
        created++;
      } catch (err) {
        errorOccurred = err;
        log(`[ERROR] Batch ingestion failed: ${err.message} (code: ${err.code}, syscall: ${err.syscall}, errno: ${err.errno})`);
        break;
      }
    }

    res.writeHead(errorOccurred ? 500 : 200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: errorOccurred ? 'ERROR' : 'OK',
      created,
      autoCloseChunks,
      error: errorOccurred ? errorOccurred.code : null
    }));
  } else if (url.pathname === '/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ pid: process.pid, autoCloseChunks }));
  } else {
    res.writeHead(404);
    res.end();
  }
});

server.listen(sockPath, () => {
  log(`Listening on UNIX domain socket ${sockPath}`);

  // Saturated initial state: allocate chunk file descriptors up to soft limit to trigger EMFILE
  if (!autoCloseChunks) {
    let softLimit = 256;
    try {
      const limits = fs.readFileSync('/proc/self/limits', 'utf8');
      const m = limits.match(/^Max open files\s+(\d+)/m);
      if (m) softLimit = parseInt(m[1], 10);
    } catch {}

    const currentFds = fs.readdirSync('/proc/self/fd').length;
    const target = softLimit - currentFds + 1;

    for (let i = 0; i < target; i++) {
      const p = path.join(chunksDir, `chunk-${String(i).padStart(4, '0')}.tmp`);
      try {
        const fd = fs.openSync(p, 'w');
        fs.writeSync(fd, `staged-chunk-${i}\n`);
        fs.unlinkSync(p);
        openChunkFds.push(fd);
      } catch (err) {
        break;
      }
    }

    // Trigger deterministic EMFILE on next open attempt
    try {
      const p = path.join(chunksDir, 'chunk-overflow.tmp');
      fs.openSync(p, 'w');
    } catch (err) {
      log(`[ERROR] Batch ingestion failed: ${err.message} (code: ${err.code}, syscall: ${err.syscall}, errno: ${err.errno})`);
    }
  }

  // Signal ready to systemctl
  try {
    fs.writeSync(readyFd, 'ready\n');
    fs.closeSync(readyFd);
  } catch {}
});

function cleanup() {
  log('worker-daemon shutting down');
  try { server.close(); } catch {}
  for (const fd of openChunkFds) {
    try { fs.closeSync(fd); } catch {}
  }
  try { fs.closeSync(logFd); } catch {}
  try { fs.unlinkSync(pidFile); } catch {}
  process.exit(0);
}

process.on('SIGTERM', cleanup);
process.on('SIGINT', cleanup);
WORKER_EOF
chmod 0755 "$BASE/bin/worker-daemon"

# 4. Provision systemctl service manager
cat << 'SYS_EOF' > "$BASE/bin/systemctl"
#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
UNIT="$BASE/systemd/system/event-collector.service"
PID_FILE="$BASE/var/run/event-collector.pid"
READY_FILE="$BASE/var/run/.ready"
INITIAL_PID_FILE="$BASE/var/run/.initial-worker.pid"
RELOAD_MARKER="$BASE/var/run/.daemon-reloaded"

COMMAND="${1:-}"
SERVICE="${2:-event-collector}"

case "$COMMAND" in
  status)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" | tr -d '[:space:]')
      if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        echo "● event-collector.service - Event Collector Batch Ingestion Service"
        echo "     Loaded: loaded ($UNIT; enabled)"
        echo "     Active: active (running) since $(stat -c %y "$PID_FILE" 2>/dev/null || date)"
        echo "   Main PID: $PID (worker-daemon)"
        if [ -f "/proc/$PID/limits" ]; then
          SOFT=$(awk '/^Max open files/ { print $4 }' "/proc/$PID/limits")
          HARD=$(awk '/^Max open files/ { print $5 }' "/proc/$PID/limits")
          echo "     Limits: Max open files=$SOFT (Soft) / $HARD (Hard)"
        fi
        if [ -d "/proc/$PID/fd" ]; then
          OPEN_FDS=$(ls -1 "/proc/$PID/fd" 2>/dev/null | wc -l)
          echo "  Open FDs: $OPEN_FDS"
        fi
        exit 0
      fi
    fi
    echo "● event-collector.service - Event Collector Batch Ingestion Service"
    echo "     Loaded: loaded ($UNIT; enabled)"
    echo "     Active: inactive (dead)"
    exit 3
    ;;

  start)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" | tr -d '[:space:]')
      if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        echo "Service event-collector is already running (PID $PID)."
        exit 0
      fi
    fi

    rm -f "$READY_FILE"

    LIMIT_NOFILE=256
    if [ -f "$UNIT" ]; then
      PARSED=$(grep -E '^[[:space:]]*LimitNOFILE=' "$UNIT" | head -n1 | cut -d= -f2- | tr -d '[:space:]' || true)
      if [ -n "$PARSED" ]; then
        LIMIT_NOFILE="$PARSED"
      fi
    fi

    SOFT_LIMIT=$(echo "$LIMIT_NOFILE" | cut -d: -f1)
    HARD_LIMIT=$(echo "$LIMIT_NOFILE" | cut -d: -f2)
    [ -n "$HARD_LIMIT" ] || HARD_LIMIT="$SOFT_LIMIT"

    (
      ulimit -Sn "$SOFT_LIMIT" 2>/dev/null || true
      ulimit -Hn "$HARD_LIMIT" 2>/dev/null || true
      exec "$BASE/bin/worker-daemon" >> "$BASE/logs/worker.log" 2>&1
    ) </dev/null >/dev/null 2>&1 &

    for i in $(seq 1 40); do
      if [ -s "$READY_FILE" ] && [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" | tr -d '[:space:]')
        if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
          if [ ! -f "$INITIAL_PID_FILE" ]; then
            echo "$PID" > "$INITIAL_PID_FILE"
          fi
          echo "Started event-collector (PID $PID, LimitNOFILE=$LIMIT_NOFILE)."
          exit 0
        fi
      fi
      sleep 0.1
    done
    echo "Error: Failed to start event-collector." >&2
    exit 1
    ;;

  stop)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE" | tr -d '[:space:]')
      if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
        kill -TERM "$PID" 2>/dev/null || true
        for i in $(seq 1 20); do
          if [ ! -d "/proc/$PID" ]; then
            break
          fi
          sleep 0.1
        done
        if [ -d "/proc/$PID" ]; then
          kill -KILL "$PID" 2>/dev/null || true
        fi
      fi
      rm -f "$PID_FILE"
    fi
    rm -f "$BASE/var/run/worker.sock" "$READY_FILE"
    echo "Stopped event-collector."
    exit 0
    ;;

  restart)
    "$0" stop "$SERVICE"
    "$0" start "$SERVICE"
    ;;

  daemon-reload)
    touch "$RELOAD_MARKER"
    echo "Reloaded systemd unit configurations."
    exit 0
    ;;

  *)
    echo "Usage: $0 {status|start|stop|restart|daemon-reload} [service]" >&2
    exit 1
    ;;
esac
SYS_EOF
chmod 0755 "$BASE/bin/systemctl"

# 5. Provision verify-fds verification tool
cat << 'VERIFY_EOF' > "$BASE/bin/verify-fds"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const http = require('http');

const baseDir = path.resolve(__dirname, '..');
const pidFile = path.join(baseDir, 'var', 'run', 'event-collector.pid');
const sockPath = path.join(baseDir, 'var', 'run', 'worker.sock');
const markerFile = path.join(baseDir, '.fd-audit.passed');

try { fs.unlinkSync(markerFile); } catch {}

if (!fs.existsSync(pidFile)) {
  console.error('[FAIL] PID file var/run/event-collector.pid missing.');
  process.exit(1);
}

const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
if (!pid || !fs.existsSync(`/proc/${pid}`)) {
  console.error(`[FAIL] Worker process ${pid} is not running.`);
  process.exit(1);
}

const limitsContent = fs.readFileSync(`/proc/${pid}/limits`, 'utf8');
const limitsMatch = limitsContent.match(/^Max open files\s+(\d+)\s+(\d+)/m);
if (!limitsMatch) {
  console.error('[FAIL] Could not parse /proc/<PID>/limits.');
  process.exit(1);
}

const softLimit = parseInt(limitsMatch[1], 10);
const hardLimit = parseInt(limitsMatch[2], 10);
if (softLimit < 4096 || hardLimit < 4096) {
  console.error(`[FAIL] Process limits insufficient: Soft=${softLimit}, Hard=${hardLimit}. Both must be >= 4096.`);
  process.exit(1);
}

// 1. Initial measurement
const fdsBefore = fs.readdirSync(`/proc/${pid}/fd`).length;

// 2. Controlled workload injection (100 event chunks)
const req = http.request({
  socketPath: sockPath,
  path: '/ingest-batch?count=100',
  method: 'POST'
}, (res) => {
  let body = '';
  res.on('data', (c) => { body += c; });
  res.on('end', () => {
    // 3. Final measurement
    const fdsAfter = fs.readdirSync(`/proc/${pid}/fd`).length;
    const growth = fdsAfter - fdsBefore;

    let deletedChunks = 0;
    try {
      const fdEntries = fs.readdirSync(`/proc/${pid}/fd`);
      for (const fd of fdEntries) {
        try {
          const target = fs.readlinkSync(`/proc/${pid}/fd/${fd}`);
          if (target.includes('chunk-') && target.includes('(deleted)')) {
            deletedChunks++;
          }
        } catch {}
      }
    } catch {}

    if (deletedChunks > 0 || growth > 2) {
      console.error(`[FAIL] Descriptor leak detected: growth=+${growth} descriptors, ${deletedChunks} unclosed deleted chunk files.`);
      process.exit(1);
    }

    const result = {
      status: 'PASSED',
      pid,
      soft_limit: softLimit,
      hard_limit: hardLimit,
      initial_fds: fdsBefore,
      final_fds: fdsAfter,
      growth,
      deleted_chunks: deletedChunks,
      timestamp: new Date().toISOString()
    };
    fs.writeFileSync(markerFile, JSON.stringify(result, null, 2) + '\n');
    console.log(`[PASS] File descriptor limits and leak audit successful! (Soft=${softLimit}, Hard=${hardLimit}, Growth=${growth}, Deleted=${deletedChunks})`);
    process.exit(0);
  });
});

req.on('error', (err) => {
  console.error(`[FAIL] Failed to communicate with worker socket: ${err.message}`);
  process.exit(1);
});

req.end();
VERIFY_EOF
chmod 0755 "$BASE/bin/verify-fds"

# 6. Start event-collector in initial broken state
"$BASE/bin/systemctl" start event-collector

# 7. Clean reports and verification marker
rm -f "$BASE/reports/fd-triage.env" "$BASE/reports/leak-investigation.env" "$BASE/.fd-audit.passed"
