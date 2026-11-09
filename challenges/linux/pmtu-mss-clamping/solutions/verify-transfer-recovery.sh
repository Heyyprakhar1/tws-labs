#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
"$INCIDENT_DIR/bin/verify-transfer"
