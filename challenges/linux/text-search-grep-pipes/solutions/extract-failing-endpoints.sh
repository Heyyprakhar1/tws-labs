awk '{print $6}' "$HOME/log-incident/reports/500-errors.log" | sort -u > "$HOME/log-incident/reports/unique-endpoints.txt"
