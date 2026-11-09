#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/privilege-incident"

"$TARGET_DIR/bin/service-daemon" start
"$TARGET_DIR/bin/verify-service"
