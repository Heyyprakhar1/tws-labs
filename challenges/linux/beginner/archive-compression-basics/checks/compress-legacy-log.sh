. "$LAB_LIB"

[ -f backup-incident/logs/legacy-audit.log.gz ] || fail "backup-incident/logs/legacy-audit.log.gz does not exist."
[ ! -f backup-incident/logs/legacy-audit.log ] || fail "Uncompressed legacy-audit.log still exists. Replace it in place with gzip."
gzip -t backup-incident/logs/legacy-audit.log.gz 2>/dev/null || fail "legacy-audit.log.gz is corrupt."
zcat backup-incident/logs/legacy-audit.log.gz 2>/dev/null | grep -q "Event record ID 50 OK" || fail "Decompressed log payload does not match expected content."
