LOG_FILE="$HOME/cron-incident/logs/backup.log"
sed -i "s|db-backup|db-backup >> $LOG_FILE 2>\&1|" "$HOME/cron-incident/crontab"
