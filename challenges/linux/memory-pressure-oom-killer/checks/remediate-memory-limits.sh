. "$LAB_LIB"

CONFIG="mem-incident/config/worker.env"
[ -f "$CONFIG" ] || fail "Configuration file mem-incident/config/worker.env missing."

BATCH_SIZE=$(grep -E '^[[:space:]]*BATCH_SIZE=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
MAX_CONCURRENCY=$(grep -E '^[[:space:]]*MAX_CONCURRENCY=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
BUFFER_MODE=$(grep -E '^[[:space:]]*BUFFER_MODE=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
MAX_MEMORY=$(grep -E '^[[:space:]]*MAX_MEMORY_MB=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
WORKER_OOM_ADJ=$(grep -E '^[[:space:]]*WORKER_OOM_SCORE_ADJ=' "$CONFIG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ -n "$BATCH_SIZE" ] || fail "BATCH_SIZE is missing in config/worker.env."
[ "$BATCH_SIZE" -le 500 ] 2>/dev/null || fail "BATCH_SIZE must be <= 500 (got '$BATCH_SIZE')."

[ -n "$MAX_CONCURRENCY" ] || fail "MAX_CONCURRENCY is missing in config/worker.env."
[ "$MAX_CONCURRENCY" -le 2 ] 2>/dev/null || fail "MAX_CONCURRENCY must be <= 2 (got '$MAX_CONCURRENCY')."

[ "$BUFFER_MODE" = "stream" ] || fail "BUFFER_MODE must be 'stream' (got '$BUFFER_MODE')."

[ -n "$MAX_MEMORY" ] || fail "MAX_MEMORY_MB is missing in config/worker.env."
[ "$MAX_MEMORY" -le 128 ] 2>/dev/null || fail "MAX_MEMORY_MB must be <= 128 (got '$MAX_MEMORY')."

[ "$WORKER_OOM_ADJ" = "500" ] || fail "WORKER_OOM_SCORE_ADJ must be 500 (got '$WORKER_OOM_ADJ')."

RELOAD_MARKER="mem-incident/var/run/.daemon-reloaded"
[ -f "$RELOAD_MARKER" ] || fail "Run ./mem-incident/bin/systemctl daemon-reload to reload configuration."

CONFIG_MTIME=$(stat -c %Y "$CONFIG" 2>/dev/null || stat -f %m "$CONFIG")
RELOAD_MTIME=$(stat -c %Y "$RELOAD_MARKER" 2>/dev/null || stat -f %m "$RELOAD_MARKER")
[ "$RELOAD_MTIME" -ge "$CONFIG_MTIME" ] || fail "Configuration was modified after last daemon-reload. Run ./mem-incident/bin/systemctl daemon-reload again."
