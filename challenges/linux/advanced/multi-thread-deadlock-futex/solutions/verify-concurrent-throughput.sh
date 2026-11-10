#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
"$BASE_DIR/bin/benchmark-concurrency"
