BASE="$HOME/fd-incident"
PID=$(cat "$BASE/var/run/event-collector.pid" | tr -d '[:space:]')
SOFT=$(awk '/^Max open files/ { print $4 }' "/proc/$PID/limits")
HARD=$(awk '/^Max open files/ { print $5 }' "/proc/$PID/limits")
FDS=$(ls -1 "/proc/$PID/fd" | wc -l)

cat << EOF > "$BASE/reports/fd-triage.env"
WORKER_PID=$PID
NOFILE_SOFT=$SOFT
NOFILE_HARD=$HARD
OPEN_FD_COUNT=$FDS
ERROR_CODE=EMFILE
FAILING_SYSCALL=open
EOF
