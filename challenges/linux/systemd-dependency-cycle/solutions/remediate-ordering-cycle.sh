#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
AUTH_FILE="$INCIDENT_DIR/config/units/payment-auth.service"

sed -i '/After=payment-api.service/d' "$AUTH_FILE"
