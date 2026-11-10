. "$LAB_LIB"

[ -f log-incident/reports/500-errors.log ] || fail "log-incident/reports/500-errors.log does not exist."
count=$(wc -l < log-incident/reports/500-errors.log 2>/dev/null | tr -d ' ' || echo 0)
[ "$count" -eq 20 ] || fail "Expected exactly 20 filtered 500 error lines (found $count)."
! grep -vq ' 500 ' log-incident/reports/500-errors.log || fail "reports/500-errors.log contains non-500 log lines."
