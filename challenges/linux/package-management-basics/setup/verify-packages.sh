#!/bin/bash
set -euo pipefail
# 1. Solve Task 1
echo "app-web" > "$HOME/pkg-incident/reports/broken-package.txt"

# 2. Solve Task 2
cp "$HOME/pkg-incident/var/lib/dpkg/status.orig" "$HOME/pkg-incident/var/lib/dpkg/status"
"$HOME/pkg-incident/bin/pkg-tool" install "$HOME/pkg-incident/pool/libmsg-proto.meta"

# 3. Solve Task 3
"$HOME/pkg-incident/bin/pkg-tool" configure app-web

# 4. Keep Task 4 broken (marker absent)
rm -f "$HOME/pkg-incident/.pkg-audit.passed"
