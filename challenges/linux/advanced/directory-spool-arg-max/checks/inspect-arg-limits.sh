. "$LAB_LIB"

REPORT="spool-incident/reports/arg-limits.env"
[ -f "$REPORT" ] || fail "Report spool-incident/reports/arg-limits.env does not exist."

ARG_MAX_VAL=$(grep -E '^[[:space:]]*SYSTEM_ARG_MAX=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
NAME_MAX_VAL=$(grep -E '^[[:space:]]*SYSTEM_NAME_MAX=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
FNAME_LEN=$(grep -E '^[[:space:]]*SAMPLE_FILENAME_LENGTH=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
ERRNO_VAL=$(grep -E '^[[:space:]]*FAILING_ERRNO=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
LIMIT_TYPE=$(grep -E '^[[:space:]]*KERNEL_LIMIT_TYPE=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ "$ARG_MAX_VAL" = "2097152" ] || fail "SYSTEM_ARG_MAX must be 2097152 (got '$ARG_MAX_VAL')."
[ "$NAME_MAX_VAL" = "255" ] || fail "SYSTEM_NAME_MAX must be 255 (got '$NAME_MAX_VAL')."
[ "$FNAME_LEN" = "245" ] || fail "SAMPLE_FILENAME_LENGTH must be 245 (got '$FNAME_LEN')."
[ "$ERRNO_VAL" = "E2BIG" ] || fail "FAILING_ERRNO must be E2BIG (got '$ERRNO_VAL')."
[ "$LIMIT_TYPE" = "ARG_MAX" ] || fail "KERNEL_LIMIT_TYPE must be ARG_MAX (got '$LIMIT_TYPE')."
