. "$LAB_LIB"

[ -f log-incident/reports/unique-endpoints.txt ] || fail "log-incident/reports/unique-endpoints.txt does not exist."
expected=$'/api/v1/checkout\n/api/v1/orders\n/api/v1/payment'
actual=$(cat log-incident/reports/unique-endpoints.txt 2>/dev/null || true)
[ "$actual" = "$expected" ] || fail "reports/unique-endpoints.txt does not match expected sorted unique list."
