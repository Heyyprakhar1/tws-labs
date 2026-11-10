#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
REPORT="$INCIDENT_DIR/reports/cycle-triage.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/cycle-triage.env not found."
    exit 1
fi

CYCLE_DETECTED=$(grep '^CYCLE_DETECTED=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CYCLE_UNITS=$(grep '^CYCLE_UNITS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CYCLE_LENGTH=$(grep '^CYCLE_LENGTH=' "$REPORT" | cut -d= -f2- | tr -d ' "')
CONFLICTING_DIRECTIVE=$(grep '^CONFLICTING_DIRECTIVE=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$CYCLE_DETECTED" != "true" ]; then
    echo "Check failed: CYCLE_DETECTED expected true, got '$CYCLE_DETECTED'."
    exit 1
fi

if [ "$CYCLE_LENGTH" != "3" ]; then
    echo "Check failed: CYCLE_LENGTH expected 3, got '$CYCLE_LENGTH'."
    exit 1
fi

if [ "$CONFLICTING_DIRECTIVE" != "After" ]; then
    echo "Check failed: CONFLICTING_DIRECTIVE expected After, got '$CONFLICTING_DIRECTIVE'."
    exit 1
fi

for u in "payment-api.service" "payment-cache.service" "payment-auth.service"; do
    if ! echo "$CYCLE_UNITS" | grep -q "$u"; then
        echo "Check failed: CYCLE_UNITS is missing expected unit '$u'."
        exit 1
    fi
done

echo "Check passed: systemd ordering cycle correctly diagnosed."
exit 0
