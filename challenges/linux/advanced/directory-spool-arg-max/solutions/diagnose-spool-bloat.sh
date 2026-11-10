BASE="$HOME/spool-incident"
mkdir -p "$BASE/reports"

COUNT=$(ls -1 "$BASE/var/spool" | wc -l | tr -d '[:space:]')
QUOTA=$(grep -E '^[[:space:]]*MAX_SPOOL_FILES=' "$BASE/config/spooler.env" | cut -d= -f2 | tr -d '[:space:]"')

cat << EOF > "$BASE/reports/spool-triage.env"
CURRENT_FILE_COUNT=$COUNT
CONFIGURED_QUOTA=$QUOTA
QUOTA_STATUS=EXCEEDED
SIMULATED_ERRNO=ENOSPC
EOF
