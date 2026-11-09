#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
grep ' 500 ' "$HOME/log-incident/logs/api-gateway.log" > "$HOME/log-incident/reports/500-errors.log"

# 2. Keep Task 2 broken
rm -f "$HOME/log-incident/reports/unique-endpoints.txt"
