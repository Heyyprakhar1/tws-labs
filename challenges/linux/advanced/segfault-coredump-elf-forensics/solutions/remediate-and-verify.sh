#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
CONF="$TARGET_DIR/config/worker.env"

cat << 'EOF' > "$CONF"
# Production Batch Worker Configuration
BATCH_SIZE=100
WORKER_CONCURRENCY=4
DATABASE_URL="postgres://app:secret@db.internal:5432/batches"
TELEMETRY_ENABLED="false"
EOF

"$TARGET_DIR/bin/verify-worker"
