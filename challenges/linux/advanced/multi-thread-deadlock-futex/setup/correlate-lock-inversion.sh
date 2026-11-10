#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/diagnose-deadlock-threads.sh"
"$SCRIPT_DIR/../solutions/correlate-lock-inversion.sh"
