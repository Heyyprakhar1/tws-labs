#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
mkdir -p "$HOME/backup-incident/restore"
tar -xzf "$HOME/backup-incident/incoming/backup-payload.bin" -C "$HOME/backup-incident/restore"

# 2. Keep Task 2 in initial broken state
rm -f "$HOME/backup-incident/logs/legacy-audit.log.gz"
if [ ! -f "$HOME/backup-incident/logs/legacy-audit.log" ]; then
  for i in {1..50}; do
    echo "2026-11-01 [AUDIT] Event record ID $i OK"
  done > "$HOME/backup-incident/logs/legacy-audit.log"
fi
