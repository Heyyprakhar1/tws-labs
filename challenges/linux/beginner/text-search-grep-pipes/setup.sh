#!/bin/bash
set -euo pipefail

BASE="$HOME/log-incident"
rm -rf "$BASE"
mkdir -p "$BASE/logs" "$BASE/reports" "$BASE/bin"

# 1. Deterministic interspersed log generator:
# Format: <date> <time> <host> <ip> <method> <uri> <status> <duration>
# Field:    $1     $2     $3    $4    $5       $6      $7       $8
# When i % 5 == 0 (20 times: 5, 10, ..., 100), emits an HTTP 500 error on 3 failing endpoints.
# Otherwise (80 times), emits an HTTP 200 on 4 healthy endpoints.
HEALTHY_ENDPOINTS=("/api/v1/login" "/api/v1/status" "/api/v1/health" "/api/v1/catalog")
FAILING_ENDPOINTS=("/api/v1/checkout" "/api/v1/orders" "/api/v1/payment")

for i in {1..100}; do
  ts=$(printf "10:%02d:%02d" $((i / 60)) $((i % 60)))
  if [ $((i % 5)) -eq 0 ]; then
    ep=${FAILING_ENDPOINTS[$(((i / 5) % 3))]}
    echo "2026-11-07 $ts gateway 192.168.1.$((60 + i)) POST $ep 500 128ms" >> "$BASE/logs/api-gateway.log"
  else
    ep=${HEALTHY_ENDPOINTS[$((i % 4))]}
    echo "2026-11-07 $ts gateway 192.168.1.$((10 + i)) GET $ep 200 45ms" >> "$BASE/logs/api-gateway.log"
  fi
done

# 2. Diagnostic collector emitting to stdout and stderr
cat << 'COLLECT_EOF' > "$BASE/bin/collect-telemetry"
#!/bin/bash
echo "TELEMETRY_SAMPLE_RATE=1.0"
echo "ACTIVE_CONNECTIONS=42"
echo "MEMORY_UTILIZATION_PCT=68.4"
echo "[WARN] Latency exceeded p95 threshold on /api/v1/checkout" >&2
echo "[ERROR] Upstream pool connection timeout (pool_id=redis_shard_2)" >&2
exit 0
COLLECT_EOF
chmod 0755 "$BASE/bin/collect-telemetry"

# 3. Remove any prior marker
rm -f "$BASE/.search-audit.passed"

# 4. Verification runner
cat << 'VERIFY_EOF' > "$BASE/verify-search"
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 1. Check Task 1 filtering
[ -f "reports/500-errors.log" ] || { echo "FAIL: reports/500-errors.log missing." >&2; exit 1; }
COUNT=$(wc -l < "reports/500-errors.log" | tr -d ' ')
if [ "$COUNT" -ne 20 ]; then
  echo "FAIL: Expected 20 filtered error lines, found $COUNT." >&2
  exit 1
fi
if grep -vq ' 500 ' "reports/500-errors.log"; then
  echo "FAIL: reports/500-errors.log contains non-500 log lines." >&2
  exit 1
fi

# 2. Check Task 2 unique endpoints
[ -f "reports/unique-endpoints.txt" ] || { echo "FAIL: reports/unique-endpoints.txt missing." >&2; exit 1; }
EXPECTED=$(cat << 'EOF'
/api/v1/checkout
/api/v1/orders
/api/v1/payment
EOF
)
ACTUAL=$(cat "reports/unique-endpoints.txt")
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "FAIL: reports/unique-endpoints.txt does not match expected unique endpoints." >&2
  exit 1
fi
EP_COUNT=$(wc -l < "reports/unique-endpoints.txt" | tr -d ' ')
if [ "$EP_COUNT" -ne 3 ]; then
  echo "FAIL: Expected exactly 3 unique endpoints, found $EP_COUNT." >&2
  exit 1
fi

# 3. Check Task 3 stream separation
[ -f "reports/telemetry.out" ] || { echo "FAIL: reports/telemetry.out missing." >&2; exit 1; }
[ -f "reports/telemetry.err" ] || { echo "FAIL: reports/telemetry.err missing." >&2; exit 1; }
grep -q "ACTIVE_CONNECTIONS=42" "reports/telemetry.out" || { echo "FAIL: telemetry.out missing stdout data." >&2; exit 1; }
grep -q "Latency exceeded" "reports/telemetry.err" || { echo "FAIL: telemetry.err missing stderr data." >&2; exit 1; }
if grep -q "Latency exceeded" "reports/telemetry.out"; then
  echo "FAIL: telemetry.out contains stderr output (streams not separated)." >&2
  exit 1
fi

cat << 'MARKER' > .search-audit.passed
{"status": "PASSED", "audit": "text-search-grep-pipes"}
MARKER
echo "SUCCESS: Log text filtering, pipelines, and stream redirection verified."
exit 0
VERIFY_EOF
chmod 0755 "$BASE/verify-search"
