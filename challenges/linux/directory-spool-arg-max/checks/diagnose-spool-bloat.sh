. "$LAB_LIB"

REPORT="spool-incident/reports/spool-triage.env"
[ -f "$REPORT" ] || fail "Report spool-incident/reports/spool-triage.env does not exist."

COUNT=$(grep -E '^[[:space:]]*CURRENT_FILE_COUNT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
QUOTA=$(grep -E '^[[:space:]]*CONFIGURED_QUOTA=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
STATUS=$(grep -E '^[[:space:]]*QUOTA_STATUS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ERR=$(grep -E '^[[:space:]]*SIMULATED_ERRNO=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ "$COUNT" = "10000" ] || fail "CURRENT_FILE_COUNT must be 10000 (got '$COUNT')."
[ "$QUOTA" = "1000" ] || fail "CONFIGURED_QUOTA must be 1000 (got '$QUOTA')."
[ "$STATUS" = "EXCEEDED" ] || fail "QUOTA_STATUS must be EXCEEDED (got '$STATUS')."
[ "$ERR" = "ENOSPC" ] || fail "SIMULATED_ERRNO must be ENOSPC (got '$ERR')."
