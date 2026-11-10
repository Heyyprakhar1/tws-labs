#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"
VERIFY="$TARGET_DIR/bin/verify-service"

if [ ! -x "$VERIFY" ]; then
    echo "Verification binary bin/verify-service missing or not executable!"
    exit 1
fi

OUT=$("$VERIFY" 2>&1) || {
    FAIL_LINE=$(echo "$OUT" | grep "FAILED:" | head -1 || true)
    echo "${FAIL_LINE:-Service verification failed}"
    exit 1
}

if ! echo "$OUT" | grep -q "Verification SUCCESS"; then
    echo "Service verification did not confirm least privilege"
    exit 1
fi

exit 0
