#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
mkdir -p "$TARGET_DIR/reports"

cat << 'EOF' > "$TARGET_DIR/reports/elf-triage.env"
ELF_CLASS=ELF64
DATA_ENCODING=2LSB
ARCHITECTURE=x86_64
CORE_PROCESS_NAME=worker_service
CRASHED_PID=12480
TERMINATING_SIGNAL=SIGSEGV
SIGNAL_NUMBER=11
SHELL_EXIT_STATUS=139
EOF
