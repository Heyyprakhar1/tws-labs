BASE="$HOME/fd-incident"
"$BASE/bin/systemctl" restart event-collector
"$BASE/bin/verify-fds"
