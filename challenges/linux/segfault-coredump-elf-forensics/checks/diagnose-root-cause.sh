#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
REPORT="$TARGET_DIR/reports/root-cause.env"

if [ ! -f "$REPORT" ]; then
    echo "Root cause report not found at reports/root-cause.env"
    exit 1
fi

FAULTING_FUNCTION=""
VULNERABLE_STRUCT_MEMBER=""
ROOT_CAUSE=""
TRIGGERING_CONFIG_KEY=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        FAULTING_FUNCTION) FAULTING_FUNCTION="$val" ;;
        VULNERABLE_STRUCT_MEMBER) VULNERABLE_STRUCT_MEMBER="$val" ;;
        ROOT_CAUSE) ROOT_CAUSE="$val" ;;
        TRIGGERING_CONFIG_KEY) TRIGGERING_CONFIG_KEY="$val" ;;
    esac
done < "$REPORT"

if [ "$FAULTING_FUNCTION" != "process_batch" ]; then
    echo "FAULTING_FUNCTION must be process_batch"
    exit 1
fi

if [ "$VULNERABLE_STRUCT_MEMBER" != "telemetry_endpoint" ]; then
    echo "VULNERABLE_STRUCT_MEMBER must be telemetry_endpoint"
    exit 1
fi

if [ "$ROOT_CAUSE" != "UNCHECKED_NULL_POINTER_DEREFERENCE" ]; then
    echo "ROOT_CAUSE must be UNCHECKED_NULL_POINTER_DEREFERENCE"
    exit 1
fi

if [ "$TRIGGERING_CONFIG_KEY" != "TELEMETRY_ENDPOINT" ]; then
    echo "TRIGGERING_CONFIG_KEY must be TELEMETRY_ENDPOINT"
    exit 1
fi

exit 0
