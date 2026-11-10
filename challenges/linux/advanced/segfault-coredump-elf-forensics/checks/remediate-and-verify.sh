#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
CONF="$TARGET_DIR/config/worker.env"
VERIFY="$TARGET_DIR/bin/verify-worker"

if [ ! -f "$CONF" ]; then
    echo "Configuration file config/worker.env missing!"
    exit 1
fi

if [ ! -x "$VERIFY" ]; then
    echo "Verification binary bin/verify-worker missing or not executable!"
    exit 1
fi

# Run verification runner
OUT=$("$VERIFY" 2>&1) || {
    echo "Worker verification failed with crash/error: $OUT"
    exit 1
}

if ! echo "$OUT" | grep -q "100/100 records processed successfully"; then
    echo "Worker verification did not process all records cleanly"
    exit 1
fi

exit 0
