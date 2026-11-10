BASE="$HOME/fd-incident"
sed -i 's/^AUTO_CLOSE_CHUNKS=.*/AUTO_CLOSE_CHUNKS=true/' "$BASE/config/worker.env"
sed -i 's/^LimitNOFILE=.*/LimitNOFILE=4096/' "$BASE/systemd/system/event-collector.service"
"$BASE/bin/systemctl" daemon-reload
