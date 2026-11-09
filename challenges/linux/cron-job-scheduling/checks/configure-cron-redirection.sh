. "$LAB_LIB"

cmd=$(grep -E '^[[:space:]]*30[[:space:]]+2' cron-incident/crontab 2>/dev/null | head -n1 || true)
echo "$cmd" | grep -Eq 'db-backup[[:space:]]+>>' || fail "Scheduled command must invoke db-backup with >> redirection."

target_log="$HOME/cron-incident/logs/backup.log"
echo "$cmd" | grep -Eq ">>[[:space:]]*$target_log[[:space:]]+2>&1" || fail "Command must redirect output to absolute path $target_log with 2>&1."
