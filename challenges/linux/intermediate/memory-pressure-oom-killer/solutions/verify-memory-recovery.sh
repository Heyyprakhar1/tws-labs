#!/bin/bash
set -euo pipefail

BASE="mem-incident"

"$BASE/bin/systemctl" restart data-aggregator
(cd "$BASE" && ./bin/verify-memory)
