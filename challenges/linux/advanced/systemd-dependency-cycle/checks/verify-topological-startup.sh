#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
REPORT="$INCIDENT_DIR/reports/recovery-report.env"
STATE_FILE="$INCIDENT_DIR/var/run/active-units.txt"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/recovery-report.env not found. Run ./bin/systemctl start payment-api."
    exit 1
fi

STARTUP_STATUS=$(grep '^STARTUP_STATUS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
ACTIVATED_UNITS=$(grep '^ACTIVATED_UNITS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CYCLES_COUNT=$(grep '^CYCLES_COUNT=' "$REPORT" | cut -d= -f2- | tr -d ' "')
TOPOLOGICAL_ORDER=$(grep '^TOPOLOGICAL_ORDER=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$STARTUP_STATUS" != "SUCCESS" ]; then
    echo "Check failed: STARTUP_STATUS expected SUCCESS, got '$STARTUP_STATUS'."
    exit 1
fi

if [ "$ACTIVATED_UNITS" != "4" ]; then
    echo "Check failed: ACTIVATED_UNITS expected 4, got '$ACTIVATED_UNITS'."
    exit 1
fi

if [ "$CYCLES_COUNT" != "0" ]; then
    echo "Check failed: CYCLES_COUNT expected 0, got '$CYCLES_COUNT'."
    exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
    echo "Check failed: var/run/active-units.txt not found."
    exit 1
fi

# Verify topological ordering constraints:
# 1. payment-cache must come after payment-auth (payment-cache has After=payment-auth)
# 2. payment-api must come after payment-cache and payment-db (payment-api has After=payment-db payment-cache)
idx_auth=$(grep -n "payment-auth.service" "$STATE_FILE" | cut -d: -f1)
idx_cache=$(grep -n "payment-cache.service" "$STATE_FILE" | cut -d: -f1)
idx_api=$(grep -n "payment-api.service" "$STATE_FILE" | cut -d: -f1)
idx_db=$(grep -n "payment-db.service" "$STATE_FILE" | cut -d: -f1)

if [ -z "$idx_auth" ] || [ -z "$idx_cache" ] || [ -z "$idx_api" ] || [ -z "$idx_db" ]; then
    echo "Check failed: One or more required services missing from active units."
    exit 1
fi

if [ "$idx_auth" -ge "$idx_cache" ]; then
    echo "Check failed: payment-auth.service (pos $idx_auth) must execute before payment-cache.service (pos $idx_cache)."
    exit 1
fi

if [ "$idx_cache" -ge "$idx_api" ]; then
    echo "Check failed: payment-cache.service (pos $idx_cache) must execute before payment-api.service (pos $idx_api)."
    exit 1
fi

if [ "$idx_db" -ge "$idx_api" ]; then
    echo "Check failed: payment-db.service (pos $idx_db) must execute before payment-api.service (pos $idx_api)."
    exit 1
fi

echo "Check passed: valid topological startup sequence and service activation verified."
exit 0
