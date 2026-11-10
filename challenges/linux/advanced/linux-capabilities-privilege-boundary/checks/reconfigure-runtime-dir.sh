#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
CONF="$TARGET_DIR/config/daemon.env"
RUN_DIR="$TARGET_DIR/var/run"

if [ ! -d "$RUN_DIR" ]; then
    echo "Runtime directory var/run does not exist at $RUN_DIR"
    exit 1
fi

if [ ! -f "$CONF" ]; then
    echo "Configuration file config/daemon.env missing!"
    exit 1
fi

PID_FILE=""
while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    if [ "$key" = "PID_FILE" ]; then
        PID_FILE="$val"
    fi
done < "$CONF"

if [ -z "$PID_FILE" ]; then
    echo "PID_FILE is not configured in config/daemon.env"
    exit 1
fi

if [[ "$PID_FILE" == "/var/run"* ]] || [[ "$PID_FILE" == "/run"* ]]; then
    echo "PID_FILE must not point to root-owned /var/run; configure it inside $TARGET_DIR/var/run"
    exit 1
fi

# Expand ~ or $HOME if present
RESOLVED_PID_FILE=$(eval echo "$PID_FILE")
if [[ "$RESOLVED_PID_FILE" != "$TARGET_DIR"* ]] && [[ "$RESOLVED_PID_FILE" != "var/run"* ]] && [[ "$RESOLVED_PID_FILE" != "./var/run"* ]]; then
    echo "PID_FILE must be located within the user-owned workspace $TARGET_DIR"
    exit 1
fi

exit 0
