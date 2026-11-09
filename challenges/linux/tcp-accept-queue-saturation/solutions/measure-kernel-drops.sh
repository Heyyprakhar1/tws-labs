BASE="$HOME/tcp-incident"
mkdir -p "$BASE/reports"

cat << 'EOF' > "$BASE/reports/metric-drops.env"
BURST_CLIENT_COUNT=20
SUCCESSFUL_CONNECTS=6
FAILED_CONNECTS=14
OVERFLOW_COUNTER=ListenOverflows
DROP_COUNTER=ListenDrops
EOF
