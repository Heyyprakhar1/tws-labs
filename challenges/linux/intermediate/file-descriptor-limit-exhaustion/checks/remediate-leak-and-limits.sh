. "$LAB_LIB"

CFG="fd-incident/config/worker.env"
[ -f "$CFG" ] || fail "Configuration file fd-incident/config/worker.env missing."

AUTO_CLOSE=$(grep -E '^[[:space:]]*AUTO_CLOSE_CHUNKS=' "$CFG" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
[ "$AUTO_CLOSE" = "true" ] || fail "AUTO_CLOSE_CHUNKS in config/worker.env must be set to true (currently '$AUTO_CLOSE')."

UNIT="fd-incident/systemd/system/event-collector.service"
[ -f "$UNIT" ] || fail "Unit file fd-incident/systemd/system/event-collector.service missing."

LIMIT=$(grep -E '^[[:space:]]*LimitNOFILE=' "$UNIT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
[ -n "$LIMIT" ] || fail "LimitNOFILE is missing from [Service] section of event-collector.service."

SOFT_VAL=$(echo "$LIMIT" | cut -d: -f1)
[ "$SOFT_VAL" -ge 4096 ] 2>/dev/null || fail "LimitNOFILE must be set to at least 4096 (currently '$LIMIT')."

RELOAD_MARKER="fd-incident/var/run/.daemon-reloaded"
[ -f "$RELOAD_MARKER" ] || fail "Run ./fd-incident/bin/systemctl daemon-reload to reload systemd service configuration."

UNIT_MTIME=$(stat -c %Y "$UNIT" 2>/dev/null || stat -f %m "$UNIT" 2>/dev/null || echo 0)
RELOAD_MTIME=$(stat -c %Y "$RELOAD_MARKER" 2>/dev/null || stat -f %m "$RELOAD_MARKER" 2>/dev/null || echo 0)
[ "$RELOAD_MTIME" -ge "$UNIT_MTIME" ] || fail "Unit file was modified after last daemon-reload. Run ./fd-incident/bin/systemctl daemon-reload again."
