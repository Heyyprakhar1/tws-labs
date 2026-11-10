. "$LAB_LIB"

REPORT="tcp-incident/reports/metric-drops.env"
[ -f "$REPORT" ] || fail "Report tcp-incident/reports/metric-drops.env does not exist."

BURST_COUNT=$(grep -E '^[[:space:]]*BURST_CLIENT_COUNT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
SUCCESS_COUNT=$(grep -E '^[[:space:]]*SUCCESSFUL_CONNECTS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
FAILED_COUNT=$(grep -E '^[[:space:]]*FAILED_CONNECTS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
OVERFLOW_NAME=$(grep -E '^[[:space:]]*OVERFLOW_COUNTER=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
DROP_NAME=$(grep -E '^[[:space:]]*DROP_COUNTER=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ "$BURST_COUNT" = "20" ] || fail "BURST_CLIENT_COUNT must be 20 (got '$BURST_COUNT')."
[ "$SUCCESS_COUNT" = "6" ] || fail "SUCCESSFUL_CONNECTS must be 6 (got '$SUCCESS_COUNT')."
[ "$FAILED_COUNT" = "14" ] || fail "FAILED_CONNECTS must be 14 (got '$FAILED_COUNT')."
[ "$OVERFLOW_NAME" = "ListenOverflows" ] || fail "OVERFLOW_COUNTER must be ListenOverflows (got '$OVERFLOW_NAME')."
[ "$DROP_NAME" = "ListenDrops" ] || fail "DROP_COUNTER must be ListenDrops (got '$DROP_NAME')."
