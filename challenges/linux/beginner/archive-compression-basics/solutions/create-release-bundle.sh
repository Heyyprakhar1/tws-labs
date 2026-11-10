mkdir -p "$HOME/backup-incident/release" && tar --exclude="*.tmp" --exclude="cache" -czf "$HOME/backup-incident/release/app-bundle.tar.gz" -C "$HOME/backup-incident" app
