BASE="$HOME/spool-incident"
sed -i 's/^MAX_SPOOL_FILES=.*/MAX_SPOOL_FILES=5000/' "$BASE/config/spooler.env"
sed -i 's/^AUTO_PURGE_ENABLED=.*/AUTO_PURGE_ENABLED=true/' "$BASE/config/spooler.env"

"$BASE/bin/spool-ctl" restart
sleep 0.5
"$BASE/bin/verify-spool"
