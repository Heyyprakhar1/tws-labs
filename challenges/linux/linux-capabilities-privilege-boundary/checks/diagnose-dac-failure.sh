#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
REPORT="$TARGET_DIR/reports/dac-incident.env"

if [ ! -f "$REPORT" ]; then
    echo "DAC diagnostic report not found at reports/dac-incident.env"
    exit 1
fi

FAILING_PATH=""
DIRECTORY_OWNER=""
DIRECTORY_MODE=""
CALLER_UID=""
FAILURE_REASON=""
PROPOSED_RESOLUTION=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        FAILING_PATH) FAILING_PATH="$val" ;;
        DIRECTORY_OWNER) DIRECTORY_OWNER="$val" ;;
        DIRECTORY_MODE) DIRECTORY_MODE="$val" ;;
        CALLER_UID) CALLER_UID="$val" ;;
        FAILURE_REASON) FAILURE_REASON="$val" ;;
        PROPOSED_RESOLUTION) PROPOSED_RESOLUTION="$val" ;;
    esac
done < "$REPORT"

if [ "$FAILING_PATH" != "/var/run/app.pid" ]; then
    echo "FAILING_PATH must be /var/run/app.pid"
    exit 1
fi

if [ "$DIRECTORY_OWNER" != "root" ] && [ "$DIRECTORY_OWNER" != "0" ]; then
    echo "DIRECTORY_OWNER must be root"
    exit 1
fi

if [ "$DIRECTORY_MODE" != "0755" ] && [ "$DIRECTORY_MODE" != "755" ]; then
    echo "DIRECTORY_MODE must be 0755"
    exit 1
fi

MY_UID=$(id -u)
if [ "$CALLER_UID" != "10000" ] && [ "$CALLER_UID" != "$MY_UID" ]; then
    echo "CALLER_UID must match current learner UID (10000)"
    exit 1
fi

if [ "$FAILURE_REASON" != "DAC_WRITE_DENIED_TO_NON_OWNER" ]; then
    echo "FAILURE_REASON must be DAC_WRITE_DENIED_TO_NON_OWNER"
    exit 1
fi

if [ "$PROPOSED_RESOLUTION" != "CONFIGURE_USER_OWNED_RUNTIME_DIR" ]; then
    echo "PROPOSED_RESOLUTION must be CONFIGURE_USER_OWNED_RUNTIME_DIR"
    exit 1
fi

exit 0
