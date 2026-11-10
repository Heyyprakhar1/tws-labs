BASE="$HOME/fd-incident"
cat << 'EOF' > "$BASE/reports/leak-investigation.env"
LEAK_FD_TYPE=file
LEAK_TARGET_PATTERN=chunk-*.tmp (deleted)
LEAK_CONFIG_FILE=config/worker.env
LEAK_CONFIG_KEY=AUTO_CLOSE_CHUNKS
ROOT_CAUSE=unclosed temporary chunk file descriptors
EOF
