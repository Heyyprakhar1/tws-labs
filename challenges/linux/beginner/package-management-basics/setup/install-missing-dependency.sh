#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
echo "app-web" > "$HOME/pkg-incident/reports/broken-package.txt"

# 2. Keep Task 2 broken (reset status from status.orig)
cp "$HOME/pkg-incident/var/lib/dpkg/status.orig" "$HOME/pkg-incident/var/lib/dpkg/status"
rm -f "$HOME/pkg-incident/etc/app-web/runtime.conf"
