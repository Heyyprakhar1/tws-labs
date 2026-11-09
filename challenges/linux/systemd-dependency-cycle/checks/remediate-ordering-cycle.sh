#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
AUTH_FILE="$INCIDENT_DIR/config/units/payment-auth.service"
ANALYZE_BIN="$INCIDENT_DIR/bin/systemd-analyze"

if [ ! -f "$AUTH_FILE" ]; then
    echo "Check failed: config/units/payment-auth.service not found."
    exit 1
fi

if grep -q "After=.*payment-api" "$AUTH_FILE"; then
    echo "Check failed: payment-auth.service still contains cyclic directive 'After=payment-api.service'."
    exit 1
fi

if ! grep -q "Requires=.*payment-api" "$AUTH_FILE"; then
    echo "Check failed: payment-auth.service must preserve 'Requires=payment-api.service' requirement."
    exit 1
fi

# Run DAG cycle check
if ! "$ANALYZE_BIN" verify >/dev/null 2>&1; then
    echo "Check failed: systemd-analyze verify reports ordering cycle still present."
    exit 1
fi

echo "Check passed: ordering cycle eliminated and unit dependency DAG validated."
exit 0
