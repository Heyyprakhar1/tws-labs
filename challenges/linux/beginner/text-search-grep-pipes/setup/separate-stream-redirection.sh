#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
grep ' 500 ' "$HOME/log-incident/logs/api-gateway.log" > "$HOME/log-incident/reports/500-errors.log"

# 2. Solve Task 2
awk '{print $6}' "$HOME/log-incident/reports/500-errors.log" | sort -u > "$HOME/log-incident/reports/unique-endpoints.txt"

# 3. Keep Task 3 broken
rm -f "$HOME/log-incident/reports/telemetry.out" "$HOME/log-incident/reports/telemetry.err"
