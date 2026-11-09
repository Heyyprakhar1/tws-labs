ABS_BIN="$HOME/cron-incident/bin"
sed -i "1s|^|PATH=$ABS_BIN:/usr/local/bin:/usr/bin:/bin\n|" "$HOME/cron-incident/crontab"
