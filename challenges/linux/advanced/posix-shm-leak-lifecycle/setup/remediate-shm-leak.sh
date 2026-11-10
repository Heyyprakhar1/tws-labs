#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/analyze-shm-lifecycle.sh"
"$SCRIPT_DIR/../solutions/remediate-shm-leak.sh"
