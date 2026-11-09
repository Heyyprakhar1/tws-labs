#!/bin/bash
set -euo pipefail
cat << 'CRON_EOF' > "$HOME/cron-incident/crontab"
# User Crontab (5-field format: minute hour day-of-month month day-of-week command)
# Jobs execute with working directory $HOME as the crontab owner.
SHELL=/bin/bash

60 25 * * * db-backup
CRON_EOF
