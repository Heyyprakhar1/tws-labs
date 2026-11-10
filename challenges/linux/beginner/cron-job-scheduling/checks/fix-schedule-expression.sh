. "$LAB_LIB"

grep -Eq '^[[:space:]]*30[[:space:]]+2[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*' cron-incident/crontab 2>/dev/null || fail "cron-incident/crontab does not contain schedule '30 2 * * *'."
