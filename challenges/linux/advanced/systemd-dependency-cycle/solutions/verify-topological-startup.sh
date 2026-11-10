#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
"$INCIDENT_DIR/bin/systemctl" start payment-api
