#!/bin/bash
set -euo pipefail

BASE="mem-incident"

sed -i 's/^BATCH_SIZE=.*/BATCH_SIZE=500/' "$BASE/config/worker.env"
sed -i 's/^MAX_CONCURRENCY=.*/MAX_CONCURRENCY=2/' "$BASE/config/worker.env"
sed -i 's/^BUFFER_MODE=.*/BUFFER_MODE=stream/' "$BASE/config/worker.env"
sed -i 's/^MAX_MEMORY_MB=.*/MAX_MEMORY_MB=128/' "$BASE/config/worker.env"
sed -i 's/^WORKER_OOM_SCORE_ADJ=.*/WORKER_OOM_SCORE_ADJ=500/' "$BASE/config/worker.env"

"$BASE/bin/systemctl" daemon-reload
