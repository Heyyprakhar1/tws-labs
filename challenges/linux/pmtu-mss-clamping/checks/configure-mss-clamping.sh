#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
ENV_FILE="$INCIDENT_DIR/config/gateway.env"
RULES_FILE="$INCIDENT_DIR/config/iptables-rules.sh"

if [ ! -f "$ENV_FILE" ]; then
    echo "Check failed: config/gateway.env not found."
    exit 1
fi

if [ ! -f "$RULES_FILE" ]; then
    echo "Check failed: config/iptables-rules.sh not found."
    exit 1
fi

MSS_CLAMPING=$(grep '^MSS_CLAMPING=' "$ENV_FILE" | cut -d= -f2- | tr -d ' "\047')
TCP_MSS=$(grep '^TCP_MSS=' "$ENV_FILE" | cut -d= -f2- | tr -d ' "\047')

if [ "$MSS_CLAMPING" != "enabled" ]; then
    echo "Check failed: MSS_CLAMPING in config/gateway.env is '$MSS_CLAMPING', expected 'enabled'."
    exit 1
fi

if [ "$TCP_MSS" != "1380" ]; then
    echo "Check failed: TCP_MSS in config/gateway.env is '$TCP_MSS', expected 1380."
    exit 1
fi

# Check iptables-rules.sh contains TCPMSS rule with set-mss 1380 or clamp-mss-to-pmtu
if ! grep -q "TCPMSS" "$RULES_FILE" || ! grep -E -q "(--set-mss[[:space:]]+1380|--clamp-mss-to-pmtu)" "$RULES_FILE"; then
    echo "Check failed: config/iptables-rules.sh is missing valid TCPMSS clamping rule (--set-mss 1380)."
    exit 1
fi

echo "Check passed: gateway TCP MSS clamping configured."
exit 0
