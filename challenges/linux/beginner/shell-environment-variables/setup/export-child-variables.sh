#!/bin/bash
set -euo pipefail
cat << 'ENV_EOF' > "$HOME/env-incident/config/profile.env"
# Service Profile Configuration
APP_REGION=us-east-1
SERVICE_TIER="critical"

APP_ENV=production
DB_PORT=5432
ENV_EOF
