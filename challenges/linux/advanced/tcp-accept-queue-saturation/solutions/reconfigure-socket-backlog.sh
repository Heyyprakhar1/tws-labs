BASE="$HOME/tcp-incident"
sed -i 's/^TCP_BACKLOG=.*/TCP_BACKLOG=128/' "$BASE/config/api.env"
sed -i 's/^WORKER_CONCURRENCY=.*/WORKER_CONCURRENCY=32/' "$BASE/config/api.env"

"$BASE/bin/api-ctl" restart
sleep 0.5
