#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/shm-incident"
"$BASE_DIR/bin/verify-shm-resilience"
