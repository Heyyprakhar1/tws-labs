#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
REPORT="$INCIDENT_DIR/reports/dag-analysis.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/dag-analysis.env not found."
    exit 1
fi

ORDERING_DIRECTIVES=$(grep '^ORDERING_DIRECTIVES=' "$REPORT" | cut -d= -f2- | tr -d ' "')
REQUIREMENT_DIRECTIVES=$(grep '^REQUIREMENT_DIRECTIVES=' "$REPORT" | cut -d= -f2- | tr -d ' "')
DEFECTIVE_UNIT=$(grep '^DEFECTIVE_UNIT=' "$REPORT" | cut -d= -f2- | tr -d ' "')
DEFECTIVE_DIRECTIVE=$(grep '^DEFECTIVE_DIRECTIVE=' "$REPORT" | cut -d= -f2- | tr -d ' "')
RESOLUTION=$(grep '^RESOLUTION=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if ! echo "$ORDERING_DIRECTIVES" | grep -q "After" || ! echo "$ORDERING_DIRECTIVES" | grep -q "Before"; then
    echo "Check failed: ORDERING_DIRECTIVES must specify 'After,Before', got '$ORDERING_DIRECTIVES'."
    exit 1
fi

if ! echo "$REQUIREMENT_DIRECTIVES" | grep -q "Requires" || ! echo "$REQUIREMENT_DIRECTIVES" | grep -q "Wants"; then
    echo "Check failed: REQUIREMENT_DIRECTIVES must specify 'Requires,Wants', got '$REQUIREMENT_DIRECTIVES'."
    exit 1
fi

if [ "$DEFECTIVE_UNIT" != "payment-auth.service" ]; then
    echo "Check failed: DEFECTIVE_UNIT expected payment-auth.service, got '$DEFECTIVE_UNIT'."
    exit 1
fi

if ! echo "$DEFECTIVE_DIRECTIVE" | grep -q "After=payment-api.service"; then
    echo "Check failed: DEFECTIVE_DIRECTIVE must specify 'After=payment-api.service', got '$DEFECTIVE_DIRECTIVE'."
    exit 1
fi

if [ "$RESOLUTION" != "REMOVE_ORDERING_EDGE" ]; then
    echo "Check failed: RESOLUTION expected REMOVE_ORDERING_EDGE, got '$RESOLUTION'."
    exit 1
fi

echo "Check passed: systemd ordering vs requirement dependencies correctly analyzed."
exit 0
