#!/bin/bash
set -euo pipefail
cat << 'ENV_EOF' > "$HOME/env-incident/config/profile.env"
# Service Profile Configuration
APP_REGION=us-east-1
SERVICE_TIER="critical"

export APP_ENV=production
export DB_PORT=5432
ENV_EOF
