. "$LAB_LIB"

SPOOL="spool-incident/var/spool"
[ -d "$SPOOL" ] || fail "Directory spool-incident/var/spool does not exist."

BATCH_COUNT=$(find "$SPOOL" -maxdepth 1 -type f -name 'batch_*.dat' | wc -l | tr -d '[:space:]')
[ "$BATCH_COUNT" -eq 0 ] || fail "Found $BATCH_COUNT batch_*.dat files remaining in $SPOOL (must be 0)."
