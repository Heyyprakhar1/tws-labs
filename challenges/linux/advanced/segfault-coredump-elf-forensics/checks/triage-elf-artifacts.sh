#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
REPORT="$TARGET_DIR/reports/elf-triage.env"

if [ ! -f "$REPORT" ]; then
    echo "Forensic triage report not found at reports/elf-triage.env"
    exit 1
fi

ELF_CLASS=""
DATA_ENCODING=""
ARCHITECTURE=""
CORE_PROCESS_NAME=""
CRASHED_PID=""
TERMINATING_SIGNAL=""
SIGNAL_NUMBER=""
SHELL_EXIT_STATUS=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        ELF_CLASS) ELF_CLASS="$val" ;;
        DATA_ENCODING) DATA_ENCODING="$val" ;;
        ARCHITECTURE) ARCHITECTURE="$val" ;;
        CORE_PROCESS_NAME) CORE_PROCESS_NAME="$val" ;;
        CRASHED_PID) CRASHED_PID="$val" ;;
        TERMINATING_SIGNAL) TERMINATING_SIGNAL="$val" ;;
        SIGNAL_NUMBER) SIGNAL_NUMBER="$val" ;;
        SHELL_EXIT_STATUS) SHELL_EXIT_STATUS="$val" ;;
    esac
done < "$REPORT"

if [ "$ELF_CLASS" != "ELF64" ]; then
    echo "ELF_CLASS must be ELF64"
    exit 1
fi

if [ "$DATA_ENCODING" != "2LSB" ]; then
    echo "DATA_ENCODING must be 2LSB (little endian)"
    exit 1
fi

if [ "$ARCHITECTURE" != "x86_64" ]; then
    echo "ARCHITECTURE must be x86_64"
    exit 1
fi

if [ "$CORE_PROCESS_NAME" != "worker_service" ]; then
    echo "CORE_PROCESS_NAME must be worker_service"
    exit 1
fi

if [ "$CRASHED_PID" != "12480" ]; then
    echo "CRASHED_PID must be 12480"
    exit 1
fi

if [ "$TERMINATING_SIGNAL" != "SIGSEGV" ]; then
    echo "TERMINATING_SIGNAL must be SIGSEGV"
    exit 1
fi

if [ "$SIGNAL_NUMBER" != "11" ]; then
    echo "SIGNAL_NUMBER must be 11"
    exit 1
fi

if [ "$SHELL_EXIT_STATUS" != "139" ]; then
    echo "SHELL_EXIT_STATUS must be 139 (128 + 11)"
    exit 1
fi

exit 0
