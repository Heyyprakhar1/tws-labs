#!/bin/bash
set -euo pipefail
ABS_BIN="$HOME/cron-incident/bin"
LOG_FILE="$HOME/cron-incident/logs/backup.log"
cat << CRON_EOF > "$HOME/cron-incident/crontab"
# User Crontab (5-field format: minute hour day-of-month month day-of-week command)
# Jobs execute with working directory \$HOME as the crontab owner.
SHELL=/bin/bash
PATH=$ABS_BIN:/usr/local/bin:/usr/bin:/bin

30 2 * * * db-backup >> $LOG_FILE 2>&1
CRON_EOF

rm -f "$HOME/cron-incident/.cron-audit.passed" "$LOG_FILE"
