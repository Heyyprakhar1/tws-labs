#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
REPORT="$TARGET_DIR/reports/capability-audit.env"

if [ ! -f "$REPORT" ]; then
    echo "Capability audit report not found at reports/capability-audit.env"
    exit 1
fi

CAP_EFF_HEX=""
CAP_BND_HEX=""
EFFECTIVE_CAPABILITY_COUNT=""
UNPRIVILEGED_PORT_START=""
PORT_80_REQUIRES_CAP_NET_BIND=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        CAP_EFF_HEX) CAP_EFF_HEX="$val" ;;
        CAP_BND_HEX) CAP_BND_HEX="$val" ;;
        EFFECTIVE_CAPABILITY_COUNT) EFFECTIVE_CAPABILITY_COUNT="$val" ;;
        UNPRIVILEGED_PORT_START) UNPRIVILEGED_PORT_START="$val" ;;
        PORT_80_REQUIRES_CAP_NET_BIND) PORT_80_REQUIRES_CAP_NET_BIND="$val" ;;
    esac
done < "$REPORT"

# Standardize hex
CAP_EFF_NORM=$(echo "$CAP_EFF_HEX" | sed 's/^0x//' | tr '[:upper:]' '[:lower:]' || true)
CAP_BND_NORM=$(echo "$CAP_BND_HEX" | sed 's/^0x//' | tr '[:upper:]' '[:lower:]' || true)

if [ "$CAP_EFF_NORM" != "0000000000000000" ] && [ "$CAP_EFF_NORM" != "0" ]; then
    echo "CAP_EFF_HEX must be 0000000000000000"
    exit 1
fi

if [ "$CAP_BND_NORM" != "00000000a80425fb" ] && [ "$CAP_BND_NORM" != "a80425fb" ]; then
    echo "CAP_BND_HEX must match container bounding set 00000000a80425fb"
    exit 1
fi

if [ "$EFFECTIVE_CAPABILITY_COUNT" != "0" ]; then
    echo "EFFECTIVE_CAPABILITY_COUNT must be 0"
    exit 1
fi

if [ "$UNPRIVILEGED_PORT_START" != "0" ]; then
    echo "UNPRIVILEGED_PORT_START must be 0"
    exit 1
fi

if [ "$PORT_80_REQUIRES_CAP_NET_BIND" != "false" ]; then
    echo "PORT_80_REQUIRES_CAP_NET_BIND must be false (allowed by sysctl ip_unprivileged_port_start=0)"
    exit 1
fi

exit 0
