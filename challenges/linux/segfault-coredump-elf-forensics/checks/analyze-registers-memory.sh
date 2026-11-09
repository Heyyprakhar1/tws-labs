#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
REPORT="$TARGET_DIR/reports/fault-analysis.env"

if [ ! -f "$REPORT" ]; then
    echo "Fault analysis report not found at reports/fault-analysis.env"
    exit 1
fi

FAULT_ADDRESS=""
FAULTING_RIP=""
CRASHING_RAX=""
SIGNAL_CODE_NAME=""
SIGNAL_CODE_VALUE=""
KERNEL_ERROR_CODE=""
ERROR_CODE_P_BIT=""
ERROR_CODE_WR_BIT=""
ERROR_CODE_US_BIT=""
VIOLATION_CATEGORY=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        FAULT_ADDRESS) FAULT_ADDRESS="$val" ;;
        FAULTING_RIP) FAULTING_RIP="$val" ;;
        CRASHING_RAX) CRASHING_RAX="$val" ;;
        SIGNAL_CODE_NAME) SIGNAL_CODE_NAME="$val" ;;
        SIGNAL_CODE_VALUE) SIGNAL_CODE_VALUE="$val" ;;
        KERNEL_ERROR_CODE) KERNEL_ERROR_CODE="$val" ;;
        ERROR_CODE_P_BIT) ERROR_CODE_P_BIT="$val" ;;
        ERROR_CODE_WR_BIT) ERROR_CODE_WR_BIT="$val" ;;
        ERROR_CODE_US_BIT) ERROR_CODE_US_BIT="$val" ;;
        VIOLATION_CATEGORY) VIOLATION_CATEGORY="$val" ;;
    esac
done < "$REPORT"

if [ "$FAULT_ADDRESS" != "0x0" ] && [ "$FAULT_ADDRESS" != "0x0000000000000000" ] && [ "$FAULT_ADDRESS" != "0" ]; then
    echo "FAULT_ADDRESS must be 0x0"
    exit 1
fi

if [ "$FAULTING_RIP" != "0x000055d7a81211e4" ] && [ "$FAULTING_RIP" != "0x55d7a81211e4" ]; then
    echo "FAULTING_RIP must be 0x000055d7a81211e4"
    exit 1
fi

if [ "$CRASHING_RAX" != "0x0000000000000000" ] && [ "$CRASHING_RAX" != "0x0" ] && [ "$CRASHING_RAX" != "0" ]; then
    echo "CRASHING_RAX must be 0x0000000000000000"
    exit 1
fi

if [ "$SIGNAL_CODE_NAME" != "SEGV_MAPERR" ]; then
    echo "SIGNAL_CODE_NAME must be SEGV_MAPERR"
    exit 1
fi

if [ "$SIGNAL_CODE_VALUE" != "1" ]; then
    echo "SIGNAL_CODE_VALUE must be 1"
    exit 1
fi

if [ "$KERNEL_ERROR_CODE" != "4" ]; then
    echo "KERNEL_ERROR_CODE must be 4"
    exit 1
fi

if [ "$ERROR_CODE_P_BIT" != "0" ]; then
    echo "ERROR_CODE_P_BIT must be 0 (page not present)"
    exit 1
fi

if [ "$ERROR_CODE_WR_BIT" != "0" ]; then
    echo "ERROR_CODE_WR_BIT must be 0 (read access)"
    exit 1
fi

if [ "$ERROR_CODE_US_BIT" != "1" ]; then
    echo "ERROR_CODE_US_BIT must be 1 (user mode)"
    exit 1
fi

if [ "$VIOLATION_CATEGORY" != "USER_READ_UNMAPPED_PAGE" ]; then
    echo "VIOLATION_CATEGORY must be USER_READ_UNMAPPED_PAGE"
    exit 1
fi

exit 0
