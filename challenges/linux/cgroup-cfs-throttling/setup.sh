#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
mkdir -p "$INCIDENT_DIR"/{bin,config,logs,reports,telemetry/cgroup,var/run}

UID_NUM=$(id -u)
PORT=$((18203 + UID_NUM - 10000))

# 1. Generate config/indexer.env
cat > "$INCIDENT_DIR/config/indexer.env" <<EOF
# Service runtime environment
PORT=${PORT}
CONFIG_FILE="${INCIDENT_DIR}/config/indexer.cgroup"
LOG_FILE="${INCIDENT_DIR}/logs/indexer.log"
LATENCY_LOG="${INCIDENT_DIR}/logs/latency.log"
PID_FILE="${INCIDENT_DIR}/var/run/indexer.pid"
TELEMETRY_DIR="${INCIDENT_DIR}/telemetry/cgroup"
EOF

# 2. Generate initial config/indexer.cgroup (restricted quota: 25000 us per 100000 us period)
cat > "$INCIDENT_DIR/config/indexer.cgroup" <<'EOF'
# Cgroup v2 CPU Bandwidth Configuration
# cpu.max syntax: <quota_us> <period_us>
# 25000 100000 = 25ms per 100ms period (0.25 CPU cores)
cpu.max: 25000 100000
EOF

# 3. Generate initial simulated cgroup v2 telemetry
cat > "$INCIDENT_DIR/telemetry/cgroup/cpu.max" <<'EOF'
25000 100000
EOF

cat > "$INCIDENT_DIR/telemetry/cgroup/cpu.stat" <<'EOF'
usage_usec 15234000
user_usec 12100000
system_usec 3134000
nr_periods 1500
nr_throttled 980
throttled_usec 48900000
EOF

# 4. Generate initial bimodal logs/latency.log
cat > "$INCIDENT_DIR/logs/latency.log" <<'EOF'
2026-11-08T09:18:01Z [query] q="user_profile:1021" cpu_time_ms=4.1 total_latency_ms=4.1 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1022" cpu_time_ms=3.9 total_latency_ms=3.9 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1023" cpu_time_ms=4.2 total_latency_ms=4.2 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1024" cpu_time_ms=4.0 total_latency_ms=4.0 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1025" cpu_time_ms=4.3 total_latency_ms=4.3 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1026" cpu_time_ms=4.1 total_latency_ms=4.1 status=OK
2026-11-08T09:18:01Z [query] q="user_profile:1027" cpu_time_ms=4.0 total_latency_ms=104.0 status=THROTTLED
2026-11-08T09:18:01Z [query] q="user_profile:1028" cpu_time_ms=4.2 total_latency_ms=104.2 status=THROTTLED
2026-11-08T09:18:01Z [query] q="user_profile:1029" cpu_time_ms=3.9 total_latency_ms=103.9 status=THROTTLED
2026-11-08T09:18:01Z [query] q="user_profile:1030" cpu_time_ms=4.1 total_latency_ms=104.1 status=THROTTLED
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=4.0 total_latency_ms=4.0 status=OK
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=3.8 total_latency_ms=3.8 status=OK
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=4.1 total_latency_ms=4.1 status=OK
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=4.0 total_latency_ms=4.0 status=OK
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=4.2 total_latency_ms=4.2 status=OK
2026-11-08T09:18:02Z [query] q="search:payment_receipt" cpu_time_ms=3.9 total_latency_ms=3.9 status=OK
2026-11-08T09:18:02Z [query] q="search:invoice_991" cpu_time_ms=4.0 total_latency_ms=104.0 status=THROTTLED
2026-11-08T09:18:02Z [query] q="search:invoice_992" cpu_time_ms=4.1 total_latency_ms=104.1 status=THROTTLED
2026-11-08T09:18:02Z [query] q="search:invoice_993" cpu_time_ms=4.3 total_latency_ms=104.3 status=THROTTLED
2026-11-08T09:18:02Z [query] q="search:invoice_994" cpu_time_ms=4.0 total_latency_ms=104.0 status=THROTTLED
EOF

# 5. Create bin/search-indexer
cat > "$INCIDENT_DIR/bin/search-indexer" <<'PYEOF'
#!/usr/bin/env python3
"""
Search Indexer Daemon with simulated Cgroup v2 CFS Bandwidth Throttling.
Processes search requests and records simulated CFS quota exhaustion.
"""
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(INCIDENT_DIR, "config", "indexer.env")
CONF_FILE = os.path.join(INCIDENT_DIR, "config", "indexer.cgroup")
STAT_FILE = os.path.join(INCIDENT_DIR, "telemetry", "cgroup", "cpu.stat")
MAX_FILE = os.path.join(INCIDENT_DIR, "telemetry", "cgroup", "cpu.max")
LATENCY_LOG = os.path.join(INCIDENT_DIR, "logs", "latency.log")

def read_config():
    quota = 25000
    period = 100000
    if os.path.exists(CONF_FILE):
        try:
            with open(CONF_FILE, "r") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("cpu.max:"):
                        parts = line.split(":", 1)[1].strip().split()
                        if len(parts) >= 2:
                            quota = 999999999 if parts[0] == "max" else int(parts[0])
                            period = int(parts[1])
                            break
        except Exception:
            pass
    return quota, period

class ThrottleTracker:
    def __init__(self):
        self.reload()

    def reload(self):
        self.quota_us, self.period_us = read_config()
        self.current_period_start = time.time()
        self.period_used_us = 0
        self.total_queries = 0
        self.throttled_queries = 0
        # Sync telemetry cpu.max
        try:
            val = "max" if self.quota_us >= 999999999 else str(self.quota_us)
            with open(MAX_FILE, "w") as f:
                f.write(f"{val} {self.period_us}\n")
        except Exception:
            pass

    def record_query(self, cpu_cost_ms=4.0):
        self.total_queries += 1
        now = time.time()
        period_sec = self.period_us / 1_000_000.0
        if (now - self.current_period_start) >= period_sec:
            self.current_period_start = now
            self.period_used_us = 0

        cost_us = int(cpu_cost_ms * 1000)
        self.period_used_us += cost_us

        # Check if quota is exhausted for this period
        if self.quota_us < 999999999 and self.period_used_us > self.quota_us:
            # CFS Throttling occurs: worker suspended until next period
            delay_ms = 100.0
            total_latency = cpu_cost_ms + delay_ms
            status = "THROTTLED"
            self.throttled_queries += 1
            self._update_stat(throttled=True)
            return total_latency, status
        else:
            total_latency = cpu_cost_ms
            status = "OK"
            self._update_stat(throttled=False)
            return total_latency, status

    def _update_stat(self, throttled=False):
        if not os.path.exists(STAT_FILE):
            return
        try:
            stats = {}
            with open(STAT_FILE, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2:
                        stats[parts[0]] = int(parts[1])
            stats["usage_usec"] = stats.get("usage_usec", 0) + 4000
            if throttled:
                stats["nr_throttled"] = stats.get("nr_throttled", 0) + 1
                stats["throttled_usec"] = stats.get("throttled_usec", 0) + 100000
            with open(STAT_FILE, "w") as f:
                for k, v in stats.items():
                    f.write(f"{k} {v}\n")
        except Exception:
            pass

tracker = ThrottleTracker()

class RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default stderr logging

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            body = (
                f'{{"status":"ok","quota_us":{tracker.quota_us},'
                f'"period_us":{tracker.period_us},'
                f'"throttled_queries":{tracker.throttled_queries}}}\n'
            )
            self.wfile.write(body.encode("utf-8"))
        elif parsed.path == "/search":
            qs = parse_qs(parsed.query)
            q = qs.get("q", ["default"])[0]
            lat_ms, status = tracker.record_query(cpu_cost_ms=4.0)

            # Log to latency.log
            try:
                log_entry = (
                    f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
                    f'[query] q="{q}" cpu_time_ms=4.0 total_latency_ms={lat_ms:.1f} status={status}\n'
                )
                with open(LATENCY_LOG, "a") as f:
                    f.write(log_entry)
            except Exception:
                pass

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            body = (
                f'{{"query":"{q}","latency_ms":{lat_ms:.1f},'
                f'"status":"{status}","results":42}}\n'
            )
            self.wfile.write(body.encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/reload":
            tracker.reload()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"reloaded"}\n')
        else:
            self.send_response(404)
            self.end_headers()

def main():
    port = 18203
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, "r") as f:
            for line in f:
                if line.startswith("PORT="):
                    port = int(line.split("=", 1)[1].strip())
    server = HTTPServer(("127.0.0.1", port), RequestHandler)
    server.serve_forever()

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INCIDENT_DIR/bin/search-indexer"

# 6. Create bin/search-ctl
cat > "$INCIDENT_DIR/bin/search-ctl" <<'SH_EOF'
#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$INCIDENT_DIR/var/run/indexer.pid"
LOG_FILE="$INCIDENT_DIR/logs/indexer.log"
ENV_FILE="$INCIDENT_DIR/config/indexer.env"

PORT=18203
if [ -f "$ENV_FILE" ]; then
    PORT=$(grep '^PORT=' "$ENV_FILE" | cut -d= -f2)
fi

case "${1:-}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "search-indexer is already running (PID $(cat "$PID_FILE"))."
            exit 0
        fi
        nohup python3 "$INCIDENT_DIR/bin/search-indexer" > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        sleep 0.3
        echo "Started search-indexer (PID $(cat "$PID_FILE")) on port $PORT."
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
            echo "Stopped search-indexer."
        else
            echo "search-indexer is not running."
        fi
        ;;
    restart)
        "$0" stop || true
        "$0" start
        ;;
    reload)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            curl -s -X POST "http://127.0.0.1:${PORT}/reload" >/dev/null || true
            echo "Reloaded search-indexer configuration."
        else
            echo "search-indexer is not running."
            exit 1
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            QUOTA=$(cat "$INCIDENT_DIR/telemetry/cgroup/cpu.max" 2>/dev/null || echo "unknown")
            echo "search-indexer is running (PID $(cat "$PID_FILE"), port $PORT, cpu.max: $QUOTA)."
        else
            echo "search-indexer is stopped."
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload|status}"
        exit 1
        ;;
esac
SH_EOF
chmod +x "$INCIDENT_DIR/bin/search-ctl"

# 7. Create bin/cgroup-metrics
cat > "$INCIDENT_DIR/bin/cgroup-metrics" <<'PYEOF'
#!/usr/bin/env python3
"""
Inspect and format Cgroup v2 telemetry and request latency logs.
"""
import os
import sys

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAT_FILE = os.path.join(INCIDENT_DIR, "telemetry", "cgroup", "cpu.stat")
MAX_FILE = os.path.join(INCIDENT_DIR, "telemetry", "cgroup", "cpu.max")
LATENCY_LOG = os.path.join(INCIDENT_DIR, "logs", "latency.log")

def show_telemetry():
    quota_us, period_us = "unknown", "unknown"
    if os.path.exists(MAX_FILE):
        with open(MAX_FILE) as f:
            parts = f.read().strip().split()
            if len(parts) >= 2:
                quota_us, period_us = parts[0], parts[1]

    stats = {}
    if os.path.exists(STAT_FILE):
        with open(STAT_FILE) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) == 2:
                    stats[parts[0]] = int(parts[1])

    nr_periods = stats.get("nr_periods", 0)
    nr_throttled = stats.get("nr_throttled", 0)
    ratio = (nr_throttled / nr_periods * 100.0) if nr_periods > 0 else 0.0

    print("=== Cgroup v2 CPU Bandwidth Telemetry ===")
    print(f"CFS Period (us):       {period_us}")
    print(f"CFS Quota (us):        {quota_us}")
    print(f"Total Periods:         {nr_periods}")
    print(f"Throttled Periods:     {nr_throttled}")
    print(f"Throttled Ratio:       {ratio:.1f}%")
    print(f"Throttled Duration:    {stats.get('throttled_usec', 0) / 1000.0:.1f} ms")

def show_latency():
    if not os.path.exists(LATENCY_LOG):
        print("No latency log found.")
        return
    latencies = []
    with open(LATENCY_LOG) as f:
        for line in f:
            if "total_latency_ms=" in line:
                try:
                    val = float(line.split("total_latency_ms=")[1].split()[0])
                    latencies.append(val)
                except Exception:
                    pass
    if not latencies:
        print("No latency samples available.")
        return
    latencies.sort()
    n = len(latencies)
    p50 = latencies[int(n * 0.50)]
    p90 = latencies[int(n * 0.90)]
    p99 = latencies[min(n - 1, int(n * 0.99))]
    base_samples = [x for x in latencies if x < 20]
    spike_samples = [x for x in latencies if x >= 50]

    print("=== Query Latency Distribution ===")
    print(f"Total Samples:         {n}")
    print(f"P50 Latency:           {p50:.1f} ms")
    print(f"P90 Latency:           {p90:.1f} ms")
    print(f"P99 Latency:           {p99:.1f} ms")
    if base_samples and spike_samples:
        avg_base = sum(base_samples) / len(base_samples)
        avg_spike = sum(spike_samples) / len(spike_samples)
        delta = avg_spike - avg_base
        print(f"Baseline Mean:         {avg_base:.1f} ms")
        print(f"Spike Mean:            {avg_spike:.1f} ms")
        print(f"Bimodal Latency Delta: {delta:.1f} ms (~100ms CFS Period Window)")

if __name__ == "__main__":
    if "--latency" in sys.argv:
        show_latency()
    else:
        show_telemetry()
PYEOF
chmod +x "$INCIDENT_DIR/bin/cgroup-metrics"

# 8. Create bin/benchmark-latency
cat > "$INCIDENT_DIR/bin/benchmark-latency" <<'PYEOF'
#!/usr/bin/env python3
"""
Latency Benchmark & Recovery Verification Runner.
Sends burst search queries, measures tail latency, and confirms zero throttling.
"""
import os
import sys
import time
import urllib.request
import json

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(INCIDENT_DIR, "config", "indexer.env")
CONF_FILE = os.path.join(INCIDENT_DIR, "config", "indexer.cgroup")
REPORT_FILE = os.path.join(INCIDENT_DIR, "reports", "recovery-verification.env")

def get_port():
    port = 18203
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("PORT="):
                    port = int(line.split("=", 1)[1].strip())
    return port

def run_benchmark():
    port = get_port()
    url = f"http://127.0.0.1:{port}/search"
    latencies = []
    throttled_count = 0

    print(f"[*] Running burst search benchmark against 127.0.0.1:{port} (20 queries)...")
    for i in range(20):
        t0 = time.time()
        try:
            req = urllib.request.urlopen(f"{url}?q=bench_item_{i}", timeout=5)
            data = json.loads(req.read().decode("utf-8"))
            lat = data.get("latency_ms", 4.0)
            if data.get("status") == "THROTTLED" or lat >= 50.0:
                throttled_count += 1
            latencies.append(lat)
        except Exception as e:
            print(f"[!] Request {i} failed: {e}")
            latencies.append(105.0)
            throttled_count += 1

    latencies.sort()
    n = len(latencies)
    p50 = latencies[int(n * 0.50)]
    p95 = latencies[int(n * 0.95)]
    p99 = latencies[min(n - 1, int(n * 0.99))]

    print("--- Benchmark Results ---")
    print(f"Total Requests:       {n}")
    print(f"P50 Latency:          {p50:.1f} ms")
    print(f"P95 Latency:          {p95:.1f} ms")
    print(f"P99 Latency:          {p99:.1f} ms")
    print(f"Throttled Periods:    {throttled_count}")

    if throttled_count > 0 or p99 >= 15.0:
        print("\n[FAIL] Tail latency degradation detected. CFS bandwidth throttling is active.")
        print(f"Observed P99 {p99:.1f} ms >= 15 ms limit. Check cgroup quota in config/indexer.cgroup.")
        sys.exit(1)
    else:
        print("\n[PASS] Zero-throttling latency recovery verified.")
        print(f"Observed P99 {p99:.1f} ms < 15 ms threshold with 0 throttled requests.")
        os.makedirs(os.path.dirname(REPORT_FILE), exist_ok=True)
        with open(REPORT_FILE, "w") as f:
            f.write("BENCHMARK_STATUS=PASS\n")
            f.write(f"MEASURED_P99_MS={p99:.1f}\n")
            f.write(f"THROTTLED_PERIODS={throttled_count}\n")
            f.write("RECOVERY_STATE=HEALTHY\n")
        print(f"Verification report written to reports/recovery-verification.env.")
        sys.exit(0)

if __name__ == "__main__":
    run_benchmark()
PYEOF
chmod +x "$INCIDENT_DIR/bin/benchmark-latency"

# 9. Start service initially
"$INCIDENT_DIR/bin/search-ctl" start
