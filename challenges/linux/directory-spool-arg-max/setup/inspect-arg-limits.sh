BASE="$HOME/spool-incident"
mkdir -p "$BASE/reports"

COUNT=$(ls -1 "$BASE/var/spool" 2>/dev/null | wc -l | tr -d '[:space:]')
QUOTA=$(grep -E '^[[:space:]]*MAX_SPOOL_FILES=' "$BASE/config/spooler.env" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]"' || echo 1000)

cat << EOF > "$BASE/reports/spool-triage.env"
CURRENT_FILE_COUNT=${COUNT:-10000}
CONFIGURED_QUOTA=${QUOTA:-1000}
QUOTA_STATUS=EXCEEDED
SIMULATED_ERRNO=ENOSPC
EOF

rm -f "$BASE/reports/arg-limits.env" "$BASE/reports/verification.marker"
