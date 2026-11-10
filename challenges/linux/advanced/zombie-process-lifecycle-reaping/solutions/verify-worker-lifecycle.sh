#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
"$INCIDENT_DIR/bin/verify-reaping"
