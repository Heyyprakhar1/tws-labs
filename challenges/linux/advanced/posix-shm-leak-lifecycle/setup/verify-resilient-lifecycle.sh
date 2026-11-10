#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/remediate-shm-leak.sh"
"$SCRIPT_DIR/../solutions/verify-resilient-lifecycle.sh"
