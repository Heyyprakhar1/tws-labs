. "$LAB_LIB"

line=$(grep -E '^[[:space:]]*PATH=' cron-incident/crontab 2>/dev/null | head -n1 || true)
[ -n "$line" ] || fail "cron-incident/crontab header must define PATH."
! echo "$line" | grep -Eq '(\$|~)' || fail "Do not use shell variables ($ or ~) in crontab PATH. Cron requires absolute paths."

target_bin="$HOME/cron-incident/bin"
cron_path=$(echo "$line" | cut -d= -f2-)
echo "$cron_path" | tr ':' '\n' | grep -qx "$target_bin" || fail "Crontab PATH must contain absolute directory $target_bin."
