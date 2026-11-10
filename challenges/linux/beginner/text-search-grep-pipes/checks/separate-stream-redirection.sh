. "$LAB_LIB"

[ -f log-incident/reports/telemetry.out ] || fail "log-incident/reports/telemetry.out is missing."
[ -f log-incident/reports/telemetry.err ] || fail "log-incident/reports/telemetry.err is missing."
grep -q "ACTIVE_CONNECTIONS=42" log-incident/reports/telemetry.out || fail "reports/telemetry.out missing stdout telemetry."
grep -q "Latency exceeded" log-incident/reports/telemetry.err || fail "reports/telemetry.err missing stderr warnings."
! grep -q "Latency exceeded" log-incident/reports/telemetry.out || fail "reports/telemetry.out must not contain stderr data."
