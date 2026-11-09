#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
mkdir -p "$HOME/backup-incident/restore"
tar -xzf "$HOME/backup-incident/incoming/backup-payload.bin" -C "$HOME/backup-incident/restore"

# 2. Solve Task 2
if [ -f "$HOME/backup-incident/logs/legacy-audit.log" ]; then
  gzip -f "$HOME/backup-incident/logs/legacy-audit.log"
fi

# 3. Keep Task 3 in initial broken state
rm -f "$HOME/backup-incident/release/app-bundle.tar.gz"
