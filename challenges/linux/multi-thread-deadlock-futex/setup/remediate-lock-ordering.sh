#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/correlate-lock-inversion.sh"
"$SCRIPT_DIR/../solutions/remediate-lock-ordering.sh"
