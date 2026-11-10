. "$LAB_LIB"

[ -d backup-incident/restore ] || fail "Directory backup-incident/restore does not exist."
[ -f backup-incident/restore/config/database.env ] || fail "backup-incident/restore/config/database.env is missing."
[ -f backup-incident/restore/data/records.db ] || fail "backup-incident/restore/data/records.db is missing."
grep -q "DB_RESTORE_HOST=10.0.0.5" backup-incident/restore/config/database.env || fail "Extracted database.env content is corrupted."
