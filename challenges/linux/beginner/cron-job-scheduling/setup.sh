#!/bin/bash
set -euo pipefail

BASE="$HOME/cron-incident"
rm -rf "$BASE"
mkdir -p "$BASE/bin" "$BASE/logs"

# 1. Target backup executable
cat << 'BACKUP_EOF' > "$BASE/bin/db-backup"
#!/bin/bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting automated database backup..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup archive db-snapshot.sql.gz written successfully."
exit 0
BACKUP_EOF
chmod 0755 "$BASE/bin/db-backup"

# 2. Defective 5-field user crontab
cat << 'CRON_EOF' > "$BASE/crontab"
# User Crontab (5-field format: minute hour day-of-month month day-of-week command)
# Jobs execute with working directory $HOME as the crontab owner.
SHELL=/bin/bash

60 25 * * * db-backup
CRON_EOF
chmod 0644 "$BASE/crontab"

# 3. Remove any prior marker
rm -f "$BASE/.cron-audit.passed"

# 4. Crontab parser and simulator runner
cat << 'VERIFY_EOF' > "$BASE/verify-cron"
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BASE_DIR="$(pwd)"

TAB="crontab"
[ -f "$TAB" ] || { echo "FAIL: crontab missing." >&2; exit 1; }

# 1. Validate 5-field schedule format: 30 2 * * *
if ! grep -Eq '^[[:space:]]*30[[:space:]]+2[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*' "$TAB"; then
  echo "FAIL: Schedule expression for 02:30 AM (30 2 * * *) not found." >&2
  exit 1
fi

# 2. Extract PATH header and enforce literal crontab semantics
PATH_LINE=$(grep -E '^[[:space:]]*PATH=' "$TAB" | head -n1 || true)
if [ -z "$PATH_LINE" ]; then
  echo "FAIL: PATH declaration missing from crontab header." >&2
  exit 1
fi

CRON_PATH=$(echo "$PATH_LINE" | cut -d= -f2-)
if echo "$CRON_PATH" | grep -Eq '(\$|~)'; then
  echo "FAIL: PATH contains unexpanded shell variable ($ or ~). Cron does not evaluate shell variables; use absolute paths." >&2
  exit 1
fi

BIN_DIR="$(pwd)/bin"
if ! echo "$CRON_PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  echo "FAIL: PATH does not contain the absolute path $BIN_DIR." >&2
  exit 1
fi

# 3. Validate command line invokes db-backup and redirects to absolute log path
CMD_LINE=$(grep -E '30[[:space:]]+2' "$TAB" | sed -E 's/^[0-9*[:space:]]+//')

echo "$CMD_LINE" | grep -Eq '^[[:space:]]*db-backup([[:space:]]|$)' || {
  echo "FAIL: Scheduled command does not invoke db-backup." >&2
  exit 1
}

LOG_FILE="$(pwd)/logs/backup.log"
if ! echo "$CMD_LINE" | grep -Eq ">>[[:space:]]*$LOG_FILE[[:space:]]+2>&1"; then
  echo "FAIL: Command line does not redirect output to absolute path $LOG_FILE (>> ...backup.log 2>&1)." >&2
  exit 1
fi

# 4. Simulate cron execution tick from $HOME (standard cron working directory)
cd "$HOME"
env -i PATH="$CRON_PATH" SHELL=/bin/bash /bin/bash -c "$CMD_LINE" || {
  echo "FAIL: Simulated cron execution failed." >&2
  exit 1
}

[ -f "$LOG_FILE" ] || { echo "FAIL: $LOG_FILE was not created by simulated execution." >&2; exit 1; }
grep -q "Starting automated database backup" "$LOG_FILE" || { echo "FAIL: $LOG_FILE missing expected backup output." >&2; exit 1; }

cd "$BASE_DIR"
cat << 'MARKER' > .cron-audit.passed
{"status": "PASSED", "audit": "cron-job-scheduling"}
MARKER
echo "SUCCESS: Crontab schedule, literal PATH, and absolute redirection verified."
exit 0
VERIFY_EOF
chmod 0755 "$BASE/verify-cron"
