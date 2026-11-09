. "$LAB_LIB"

REPORT="fd-incident/reports/leak-investigation.env"
[ -f "$REPORT" ] || fail "Report fd-incident/reports/leak-investigation.env does not exist."

FD_TYPE=$(grep -E '^[[:space:]]*LEAK_FD_TYPE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
PATTERN=$(grep -E '^[[:space:]]*LEAK_TARGET_PATTERN=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '"' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
CFG_FILE=$(grep -E '^[[:space:]]*LEAK_CONFIG_FILE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CFG_KEY=$(grep -E '^[[:space:]]*LEAK_CONFIG_KEY=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ROOT_CAUSE=$(grep -E '^[[:space:]]*ROOT_CAUSE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '"' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)

[ "$FD_TYPE" = "file" ] || fail "LEAK_FD_TYPE must be file (got '$FD_TYPE')."
echo "$PATTERN" | grep -q "chunk-" || fail "LEAK_TARGET_PATTERN must identify chunk temporary files (got '$PATTERN')."
echo "$PATTERN" | grep -q "deleted" || fail "LEAK_TARGET_PATTERN must identify deleted files (got '$PATTERN')."
[ "$CFG_FILE" = "config/worker.env" ] || fail "LEAK_CONFIG_FILE must be config/worker.env (got '$CFG_FILE')."
[ "$CFG_KEY" = "AUTO_CLOSE_CHUNKS" ] || fail "LEAK_CONFIG_KEY must be AUTO_CLOSE_CHUNKS (got '$CFG_KEY')."
[ -n "$ROOT_CAUSE" ] || fail "ROOT_CAUSE must not be empty."
