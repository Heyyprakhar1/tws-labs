#!/bin/bash
set -euo pipefail

# 1. Base Resolution Decision Sequence
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

INCIDENT_ROOT="$CANONICAL_BASE/mem-incident"

# Teardown any existing processes if directory exists
if [ -d "$INCIDENT_ROOT" ]; then
  if [ -f "$INCIDENT_ROOT/var/run/supervisor.pid" ]; then
    SPID=$(cat "$INCIDENT_ROOT/var/run/supervisor.pid" 2>/dev/null | tr -d '[:space:]')
    [ -n "$SPID" ] && kill -KILL "$SPID" 2>/dev/null || true
  fi
  if [ -f "$INCIDENT_ROOT/var/run/worker.pid" ]; then
    WPID=$(cat "$INCIDENT_ROOT/var/run/worker.pid" 2>/dev/null | tr -d '[:space:]')
    [ -n "$WPID" ] && kill -KILL "$WPID" 2>/dev/null || true
  fi
fi

rm -rf "$INCIDENT_ROOT"
mkdir -p "$INCIDENT_ROOT/bin" \
         "$INCIDENT_ROOT/config" \
         "$INCIDENT_ROOT/systemd/system" \
         "$INCIDENT_ROOT/logs" \
         "$INCIDENT_ROOT/reports" \
         "$INCIDENT_ROOT/cgroup" \
         "$INCIDENT_ROOT/var/run"

# 2. Defective Worker Configuration
cat << 'EOF' > "$INCIDENT_ROOT/config/worker.env"
# Data Aggregator Ingestion Worker Configuration
SERVICE_NAME=data-aggregator
BATCH_SIZE=50000
MAX_CONCURRENCY=16
BUFFER_MODE=unbounded
MAX_MEMORY_MB=1024
WORKER_OOM_SCORE_ADJ=0
LOG_LEVEL=info
EOF
chmod 0644 "$INCIDENT_ROOT/config/worker.env"

# 3. Systemd Unit File
cat << 'EOF' > "$INCIDENT_ROOT/systemd/system/data-aggregator.service"
[Unit]
Description=Data Aggregator Batch Ingestion Service
After=network.target

[Service]
Type=simple
ExecStart=bin/data-aggregator-supervisor
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$INCIDENT_ROOT/systemd/system/data-aggregator.service"

# 4. Provision Node.js Worker Daemon
cat << 'WORKER_EOF' > "$INCIDENT_ROOT/bin/data-aggregator-worker"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const http = require('http');

const baseDir = path.resolve(__dirname, '..');
const configPath = path.join(baseDir, 'config', 'worker.env');
const pidFile = path.join(baseDir, 'var', 'run', 'worker.pid');
const sockPath = path.join(baseDir, 'var', 'run', 'worker.sock');
const logFile = path.join(baseDir, 'logs', 'worker.log');
const readyFile = path.join(baseDir, 'var', 'run', '.ready');

fs.mkdirSync(path.dirname(pidFile), { recursive: true });
fs.mkdirSync(path.dirname(logFile), { recursive: true });

const logFd = fs.openSync(logFile, 'a');
function log(msg) {
  try {
    fs.writeSync(logFd, `[${new Date().toISOString()}] ${msg}\n`);
  } catch {}
}

// Parse worker configuration
let batchSize = 50000;
let maxConcurrency = 16;
let bufferMode = 'unbounded';
let workerOomScoreAdj = 0;

try {
  if (fs.existsSync(configPath)) {
    const raw = fs.readFileSync(configPath, 'utf8');
    const getVal = (key) => {
      const m = raw.match(new RegExp(`^${key}\\s*=\\s*([^\\n#]+)`, 'm'));
      return m ? m[1].trim() : null;
    };
    if (getVal('BATCH_SIZE')) batchSize = parseInt(getVal('BATCH_SIZE'), 10);
    if (getVal('MAX_CONCURRENCY')) maxConcurrency = parseInt(getVal('MAX_CONCURRENCY'), 10);
    if (getVal('BUFFER_MODE')) bufferMode = getVal('BUFFER_MODE');
    if (getVal('WORKER_OOM_SCORE_ADJ')) workerOomScoreAdj = parseInt(getVal('WORKER_OOM_SCORE_ADJ'), 10);
  }
} catch (e) {
  log(`Error reading config: ${e.message}`);
}

// Apply positive oom_score_adj if configured (unprivileged processes can raise this value)
if (workerOomScoreAdj > 0) {
  try {
    fs.writeFileSync('/proc/self/oom_score_adj', String(workerOomScoreAdj));
    log(`Applied oom_score_adj=${workerOomScoreAdj} to worker PID ${process.pid}`);
  } catch (e) {
    log(`Warning: Failed to set oom_score_adj: ${e.message}`);
  }
}

fs.writeFileSync(pidFile, String(process.pid));
log(`data-aggregator-worker started (PID ${process.pid}, BATCH_SIZE=${batchSize}, CONCURRENCY=${maxConcurrency}, BUFFER=${bufferMode}, OOM_ADJ=${workerOomScoreAdj})`);

let activeRequests = 0;
let maxObservedConcurrency = 0;
let processedBatches = 0;
const retainedBuffers = [];

try { fs.unlinkSync(sockPath); } catch {}

const server = http.createServer((req, res) => {
  if (req.url === '/batch') {
    if (activeRequests >= maxConcurrency) {
      res.writeHead(429, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Too Many Requests', activeRequests, maxConcurrency }));
      return;
    }

    activeRequests++;
    if (activeRequests > maxObservedConcurrency) {
      maxObservedConcurrency = activeRequests;
    }

    let rawData = '';
    req.on('data', chunk => {
      rawData += chunk;
      if (bufferMode === 'unbounded') {
        // In unbounded mode, retain raw string buffer copies to simulate memory leak
        retainedBuffers.push(Buffer.from(chunk));
      }
    });

    req.on('end', () => {
      try {
        const items = JSON.parse(rawData);
        let transformed = 0;
        for (let i = 0; i < items.length; i++) {
          if (items[i] && items[i].id !== undefined) transformed++;
        }
        processedBatches++;

        setTimeout(() => {
          activeRequests--;
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'ok', processed: transformed, batchIndex: processedBatches }));
        }, 15);
      } catch (err) {
        activeRequests--;
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
  } else if (req.url === '/stats') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      pid: process.pid,
      processedBatches,
      maxObservedConcurrency,
      activeRequests,
      bufferMode,
      batchSize,
      rssBytes: process.memoryUsage().rss
    }));
  } else if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', pid: process.pid }));
  } else {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
  }
});

server.listen(sockPath, () => {
  log(`Worker listening on unix socket: ${sockPath}`);
  try {
    fs.writeFileSync(readyFile, 'ready\n');
  } catch {}
});

function cleanup() {
  log('data-aggregator-worker shutting down');
  try { server.close(); } catch {}
  try { fs.closeSync(logFd); } catch {}
  try { fs.unlinkSync(pidFile); } catch {}
  try { fs.unlinkSync(sockPath); } catch {}
  process.exit(0);
}

process.on('SIGTERM', cleanup);
process.on('SIGINT', cleanup);
WORKER_EOF
chmod 0755 "$INCIDENT_ROOT/bin/data-aggregator-worker"

# 5. Provision Supervisor Process
cat << 'SUPERVISOR_EOF' > "$INCIDENT_ROOT/bin/data-aggregator-supervisor"
#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$BASE/var/run/supervisor.pid"
WORKER_PID_FILE="$BASE/var/run/worker.pid"
LOG_FILE="$BASE/logs/supervisor.log"
CONFIG_FILE="$BASE/config/worker.env"
WORKER_BIN="$BASE/bin/data-aggregator-worker"

echo "$$" > "$PID_FILE"

SHUTDOWN=0
cleanup() {
  SHUTDOWN=1
  if [ -f "$WORKER_PID_FILE" ]; then
    WPID=$(cat "$WORKER_PID_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$WPID" ] && [ -d "/proc/$WPID" ]; then
      kill -TERM "$WPID" 2>/dev/null || true
      for i in $(seq 1 20); do
        [ ! -d "/proc/$WPID" ] && break
        sleep 0.1
      done
      kill -KILL "$WPID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE" "$WORKER_PID_FILE" "$BASE/var/run/worker.sock" "$BASE/var/run/.ready"
  exit 0
}

trap cleanup TERM INT

while [ "$SHUTDOWN" -eq 0 ]; do
  MAX_MEM=128
  if [ -f "$CONFIG_FILE" ]; then
    PARSED_MEM=$(grep -E '^[[:space:]]*MAX_MEMORY_MB=' "$CONFIG_FILE" | head -n1 | cut -d= -f2- | tr -d '[:space:]' || true)
    if [ -n "$PARSED_MEM" ]; then
      MAX_MEM="$PARSED_MEM"
    fi
  fi

  export NODE_OPTIONS="--max-old-space-size=$MAX_MEM"

  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] Spawning worker process..." >> "$LOG_FILE"
  "$WORKER_BIN" >> "$BASE/logs/worker.log" 2>&1 &
  CHILD_PID=$!
  echo "$CHILD_PID" > "$WORKER_PID_FILE"

  set +e
  wait "$CHILD_PID"
  EXIT_STATUS=$?
  set -e

  if [ "$SHUTDOWN" -eq 1 ]; then
    break
  fi

  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] Worker (PID $CHILD_PID) terminated with exit code $EXIT_STATUS" >> "$LOG_FILE"
  sleep 0.4
done
SUPERVISOR_EOF
chmod 0755 "$INCIDENT_ROOT/bin/data-aggregator-supervisor"

# 6. Provision Local systemctl Service Manager
cat << 'SYS_EOF' > "$INCIDENT_ROOT/bin/systemctl"
#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
UNIT="$BASE/systemd/system/data-aggregator.service"
SUPERVISOR_PID_FILE="$BASE/var/run/supervisor.pid"
WORKER_PID_FILE="$BASE/var/run/worker.pid"
READY_FILE="$BASE/var/run/.ready"
INITIAL_PID_FILE="$BASE/var/run/.initial-worker.pid"
INITIAL_SUPERVISOR_PID_FILE="$BASE/var/run/.initial-supervisor.pid"
RELOAD_MARKER="$BASE/var/run/.daemon-reloaded"

COMMAND="${1:-}"
SERVICE="${2:-data-aggregator}"

case "$COMMAND" in
  status)
    if [ -f "$SUPERVISOR_PID_FILE" ]; then
      SPID=$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$SPID" ] && [ -d "/proc/$SPID" ]; then
        echo "● data-aggregator.service - Data Aggregator Batch Ingestion Service"
        echo "     Loaded: loaded ($UNIT; enabled)"
        echo "     Active: active (running) since $(stat -c %y "$SUPERVISOR_PID_FILE" 2>/dev/null || date)"
        echo "   Main PID: $SPID (data-aggregator-supervisor)"
        
        WPID=""
        if [ -f "$WORKER_PID_FILE" ]; then
          WPID=$(cat "$WORKER_PID_FILE" 2>/dev/null | tr -d '[:space:]')
        fi
        
        if [ -n "$WPID" ] && [ -d "/proc/$WPID" ]; then
          W_RSS=$(awk '/^VmRSS:/ {print $2 " " $3}' "/proc/$WPID/status" 2>/dev/null || echo "unknown")
          W_ADJ=$(cat "/proc/$WPID/oom_score_adj" 2>/dev/null || echo "0")
          echo "     Tasks: 2 (limit: 512)"
          echo "    Memory: $W_RSS"
          echo "    CGroup: /data-aggregator.service"
          echo "            ├─$SPID /bin/bash $BASE/bin/data-aggregator-supervisor (oom_score_adj: 0)"
          echo "            └─$WPID node $BASE/bin/data-aggregator-worker (oom_score_adj: $W_ADJ)"
        else
          echo "     Tasks: 1"
          echo "    CGroup: /data-aggregator.service"
          echo "            └─$SPID /bin/bash $BASE/bin/data-aggregator-supervisor (oom_score_adj: 0)"
        fi
        exit 0
      fi
    fi
    echo "● data-aggregator.service - Data Aggregator Batch Ingestion Service"
    echo "     Loaded: loaded ($UNIT; enabled)"
    echo "     Active: inactive (dead)"
    exit 3
    ;;

  start)
    if [ -f "$SUPERVISOR_PID_FILE" ]; then
      SPID=$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$SPID" ] && [ -d "/proc/$SPID" ]; then
        echo "Service data-aggregator is already running (PID $SPID)."
        exit 0
      fi
    fi

    rm -f "$READY_FILE"
    (
      exec "$BASE/bin/data-aggregator-supervisor" >> "$BASE/logs/supervisor.log" 2>&1
    ) </dev/null >/dev/null 2>&1 &

    for i in $(seq 1 40); do
      if [ -s "$READY_FILE" ] && [ -f "$WORKER_PID_FILE" ]; then
        WPID=$(cat "$WORKER_PID_FILE" | tr -d '[:space:]')
        if [ -n "$WPID" ] && [ -d "/proc/$WPID" ]; then
          if [ ! -f "$INITIAL_PID_FILE" ]; then
            echo "$WPID" > "$INITIAL_PID_FILE"
          fi
          if [ ! -f "$INITIAL_SUPERVISOR_PID_FILE" ]; then
            cat "$SUPERVISOR_PID_FILE" > "$INITIAL_SUPERVISOR_PID_FILE"
          fi
          echo "Started data-aggregator (Supervisor PID $(cat "$SUPERVISOR_PID_FILE"), Worker PID $WPID)."
          exit 0
        fi
      fi
      sleep 0.1
    done
    echo "Error: Failed to start data-aggregator." >&2
    exit 1
    ;;

  stop)
    if [ -f "$SUPERVISOR_PID_FILE" ]; then
      SPID=$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$SPID" ] && [ -d "/proc/$SPID" ]; then
        kill -TERM "$SPID" 2>/dev/null || true
        for i in $(seq 1 20); do
          [ ! -d "/proc/$SPID" ] && break
          sleep 0.1
        done
        [ -d "/proc/$SPID" ] && kill -KILL "$SPID" 2>/dev/null || true
      fi
      rm -f "$SUPERVISOR_PID_FILE"
    fi

    if [ -f "$WORKER_PID_FILE" ]; then
      WPID=$(cat "$WORKER_PID_FILE" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$WPID" ] && [ -d "/proc/$WPID" ]; then
        kill -KILL "$WPID" 2>/dev/null || true
      fi
      rm -f "$WORKER_PID_FILE"
    fi

    rm -f "$BASE/var/run/worker.sock" "$READY_FILE"
    echo "Stopped data-aggregator."
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
chmod 0755 "$INCIDENT_ROOT/bin/systemctl"

# 7. Provision Workload Verification Tool (bin/verify-memory)
cat << 'VERIFY_EOF' > "$INCIDENT_ROOT/bin/verify-memory"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');

const baseDir = path.resolve(__dirname, '..');
const sockPath = path.join(baseDir, 'var', 'run', 'worker.sock');
const workerPidFile = path.join(baseDir, 'var', 'run', 'worker.pid');
const supervisorPidFile = path.join(baseDir, 'var', 'run', 'supervisor.pid');
const configPath = path.join(baseDir, 'config', 'worker.env');
const markerFile = path.join(baseDir, 'reports', '.memory-verified');

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
}

if (!fs.existsSync(sockPath)) {
  fail(`Worker socket not found: ${sockPath}. Is the service running?`);
}

if (!fs.existsSync(workerPidFile)) {
  fail('Worker PID file not found.');
}
const workerPid = parseInt(fs.readFileSync(workerPidFile, 'utf8').trim(), 10);
if (!workerPid || !fs.existsSync(`/proc/${workerPid}`)) {
  fail(`Worker process ${workerPid} is not active.`);
}

let supervisorPid = 0;
if (fs.existsSync(supervisorPidFile)) {
  supervisorPid = parseInt(fs.readFileSync(supervisorPidFile, 'utf8').trim(), 10);
}

// Read current config
let maxConcurrency = 2;
let batchSize = 500;
let bufferMode = 'stream';
let workerOomScoreAdj = 0;

try {
  const conf = fs.readFileSync(configPath, 'utf8');
  const getVal = (k) => {
    const m = conf.match(new RegExp(`^${k}\\s*=\\s*([^\\n#]+)`, 'm'));
    return m ? m[1].trim() : null;
  };
  if (getVal('MAX_CONCURRENCY')) maxConcurrency = parseInt(getVal('MAX_CONCURRENCY'), 10);
  if (getVal('BATCH_SIZE')) batchSize = parseInt(getVal('BATCH_SIZE'), 10);
  if (getVal('BUFFER_MODE')) bufferMode = getVal('BUFFER_MODE');
  if (getVal('WORKER_OOM_SCORE_ADJ')) workerOomScoreAdj = parseInt(getVal('WORKER_OOM_SCORE_ADJ'), 10);
} catch (e) {
  fail(`Failed to read config: ${e.message}`);
}

if (bufferMode === 'unbounded') {
  fail('BUFFER_MODE is still set to "unbounded". Switch to "stream" with backpressure.');
}
if (batchSize > 1000) {
  fail(`BATCH_SIZE (${batchSize}) is too high. Set BATCH_SIZE=500 to bound chunk allocations.`);
}
if (maxConcurrency > 4) {
  fail(`MAX_CONCURRENCY (${maxConcurrency}) exceeds safe limits. Set MAX_CONCURRENCY=2.`);
}

// Dispatch 50 batches enforcing client concurrency <= 2
const totalBatches = 50;
let peakRssKb = 0;
let concurrencyViolations = 0;

function readWorkerRss() {
  try {
    const status = fs.readFileSync(`/proc/${workerPid}/status`, 'utf8');
    const m = status.match(/^VmRSS:\s+(\d+)\s+kB/m);
    if (m) {
      const kb = parseInt(m[1], 10);
      if (kb > peakRssKb) peakRssKb = kb;
    }
  } catch {}
}

readWorkerRss();

const sampler = setInterval(readWorkerRss, 30);

function sendBatch(idx) {
  return new Promise((resolve, reject) => {
    const records = [];
    for (let i = 0; i < 500; i++) {
      records.push({ id: i, batch: idx, telemetry: 'metric-payload-stream' });
    }
    const payload = JSON.stringify(records);

    const req = http.request({
      socketPath: sockPath,
      path: '/batch',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    }, (res) => {
      let body = '';
      res.on('data', d => { body += d; });
      res.on('end', () => {
        if (res.statusCode === 429) {
          concurrencyViolations++;
          reject(new Error('Concurrency limit exceeded on worker'));
        } else if (res.statusCode === 200) {
          resolve();
        } else {
          reject(new Error(`Worker responded with HTTP ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

(async () => {
  console.log(`Starting load test: ${totalBatches} batches, client concurrency limit: ${maxConcurrency}...`);
  let inFlight = 0;
  let batchIndex = 0;
  let completed = 0;

  await new Promise((resolve, reject) => {
    function pump() {
      while (inFlight < maxConcurrency && batchIndex < totalBatches) {
        const currentIdx = batchIndex++;
        inFlight++;
        sendBatch(currentIdx).then(() => {
          inFlight--;
          completed++;
          if (completed === totalBatches) {
            resolve();
          } else {
            pump();
          }
        }).catch(err => {
          clearInterval(sampler);
          reject(err);
        });
      }
    }
    pump();
  });

  clearInterval(sampler);
  readWorkerRss();

  console.log(`Load test completed: ${completed}/${totalBatches} batches processed.`);
  console.log(`Measured Worker Peak RSS: ${peakRssKb} kB (${(peakRssKb / 1024).toFixed(1)} MB).`);

  if (concurrencyViolations > 0) {
    fail(`Observed ${concurrencyViolations} concurrency violations (HTTP 429).`);
  }

  // Acceptance bounds: 40 MB <= peak <= 90 MB (92,160 kB)
  if (peakRssKb > 92160) {
    fail(`Peak RSS (${peakRssKb} kB) exceeds maximum allowed threshold of 92160 kB (90 MB).`);
  }
  if (peakRssKb < 40000) {
    fail(`Measured Peak RSS (${peakRssKb} kB) is unrealistically low; worker process may not have executed workload.`);
  }

  // Verify supervisor is still alive
  if (supervisorPid > 0 && !fs.existsSync(`/proc/${supervisorPid}`)) {
    fail('Supervisor process was terminated during workload execution.');
  }

  // Canonical serialization and SHA-256 calculation
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const exitCode = 0;
  const status = 'PASSED';

  // Format: TIMESTAMP:TOTAL_BATCHES:MAX_CONCURRENCY:PEAK_RSS_KB:EXIT_CODE:STATUS
  const canonicalPayload = `${timestamp}:${totalBatches}:${maxConcurrency}:${peakRssKb}:${exitCode}:${status}`;
  const checksum = crypto.createHash('sha256').update(canonicalPayload).digest('hex');

  const markerContent = [
    `TIMESTAMP=${timestamp}`,
    `TOTAL_BATCHES=${totalBatches}`,
    `MAX_CONCURRENCY=${maxConcurrency}`,
    `PEAK_RSS_KB=${peakRssKb}`,
    `EXIT_CODE=${exitCode}`,
    `STATUS=${status}`,
    `CHECKSUM=${checksum}`,
    ''
  ].join('\n');

  fs.mkdirSync(path.dirname(markerFile), { recursive: true });
  fs.writeFileSync(markerFile, markerContent, 'utf8');

  console.log('AUDIT PASSED: Memory containment and workload recovery verified.');
  console.log(`Verification marker written to: ${markerFile}`);
  process.exit(0);
})().catch(err => {
  clearInterval(sampler);
  fail(`Workload verification failed: ${err.message}`);
});
VERIFY_EOF
chmod 0755 "$INCIDENT_ROOT/bin/verify-memory"

# 8. Seed Cgroup Telemetry (Historical Evidence from 08:42:14 Incident)
cat << 'EOF' > "$INCIDENT_ROOT/cgroup/memory.max"
268435456
EOF

cat << 'EOF' > "$INCIDENT_ROOT/cgroup/memory.current"
258867200
EOF

cat << 'EOF' > "$INCIDENT_ROOT/cgroup/memory.events"
low 0
high 0
max 1
oom 1
oom_kill 1
oom_group_kill 0
EOF

cat << 'EOF' > "$INCIDENT_ROOT/cgroup/memory.events.local"
low 0
high 0
max 1
oom 1
oom_kill 1
oom_group_kill 0
EOF

# 9. Seed Historical Incident Logs
cat << 'EOF' > "$INCIDENT_ROOT/logs/kernel.log"
[   1842.109201] data-aggregator invoked oom-killer: gfp_mask=0x1100cca(GFP_HIGHUSER_MOVABLE), order=0, oom_score_adj=0
[   1842.109208] CPU: 1 PID: 4128 Comm: data-aggregator-ingest Not tainted 6.6.0-generic #1
[   1842.109212] Hardware name: Cloud Virtual Machine/Standard, BIOS 1.0.0 05/18/2022
[   1842.109215] Call Trace:
[   1842.109218]  <TASK>
[   1842.109221]  dump_header+0x7f/0x210
[   1842.109228]  mem_cgroup_out_of_memory+0x112/0x140
[   1842.109234]  try_charge_memcg+0x4d8/0x7b0
[   1842.109240]  charge_memcg+0x34/0x80
[   1842.109245]  __handle_mm_fault+0x921/0x13c0
[   1842.109252]  handle_mm_fault+0x12c/0x310
[   1842.109258]  do_user_addr_fault+0x1e8/0x650
[   1842.109264]  exc_page_fault+0x77/0x170
[   1842.109270]  asm_exc_page_fault+0x27/0x30
[   1842.109276]  </TASK>
[   1842.109280] memory: usage 262144kB, limit 262144kB, failcnt 4218
[   1842.109284] swap: usage 0kB, limit 0kB, failcnt 0
[   1842.109287] Memory cgroup stats for /data-aggregator.service:
[   1842.109290] anon 254124032
[   1842.109292] file 4194304
[   1842.109294] kernel_stack 16384
[   1842.109296] pagetables 1507328
[   1842.109298] percpu 0
[   1842.109300] sock 0
[   1842.109302] shmem 0
[   1842.109304] file_mapped 1048576
[   1842.109306] file_dirty 0
[   1842.109308] file_writeback 0
[   1842.109310] Tasks state (memory values in pages):
[   1842.109313] [  pid  ]   uid  tgid total_vm      rss pgtables_bytes swapents oom_score_adj name
[   1842.109318] [   4127]  1000  4127     5120      812          40960        0             0 data-aggregator-supervisor
[   1842.109325] [   4128]  1000  4128    12480     2410          73728        0             0 data-aggregator-ingest
[   1842.109332] [   4129]  1000  4129    78940    62080         524288        0             0 data-aggregator-worker
[   1842.109340] Memory cgroup out of memory: Killed process 4129 (data-aggregator-worker) total-vm:315760kB, anon-rss:248320kB, file-rss:0kB, shmem-rss:0kB, UID:1000 pgtables:512kB oom_score_adj:0
EOF

cat << 'EOF' > "$INCIDENT_ROOT/logs/supervisor.log"
[2026-11-08T08:40:00Z] [INFO] Spawning worker process (PID 4129)...
[2026-11-08T08:42:14Z] [WARN] Worker (PID 4129) terminated with exit code 137
[2026-11-08T08:42:15Z] [INFO] Immediate restart triggered by supervisor
EOF

cat << 'EOF' > "$INCIDENT_ROOT/logs/worker.log"
[2026-11-08T08:40:02Z] data-aggregator-worker started (PID 4129, BATCH_SIZE=50000, CONCURRENCY=16, BUFFER=unbounded, OOM_ADJ=0)
[2026-11-08T08:41:30Z] Ingestion throughput: 14200 items/sec
[2026-11-08T08:42:10Z] [WARN] High memory watermark exceeded: active RSS 245MB / limit 256MB
EOF

# 10. Start the Service via local systemctl
"$INCIDENT_ROOT/bin/systemctl" start data-aggregator
