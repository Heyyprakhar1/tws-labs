#!/bin/bash
set -euo pipefail

BASE="$HOME/env-incident"
rm -rf "$BASE"
mkdir -p "$BASE/bin" "$BASE/config"

# 1. Provision target binary requiring inherited environment
cat << 'BIN_EOF' > "$BASE/bin/svc-ctl"
#!/bin/bash
set -euo pipefail
if [ "${APP_ENV:-}" != "production" ] || [ "${DB_PORT:-}" != "5432" ]; then
  echo "FAIL: Missing required environment variables (APP_ENV=production, DB_PORT=5432)." >&2
  exit 1
fi
echo "SVC-CTL-OK"
exit 0
BIN_EOF
chmod 0755 "$BASE/bin/svc-ctl"

# 2. Provision defective profile
cat << 'ENV_EOF' > "$BASE/config/profile.env"
# Service Profile Configuration
APP_REGION = us-east-1
SERVICE_TIER="critical

APP_ENV=production
DB_PORT=5432
ENV_EOF
chmod 0644 "$BASE/config/profile.env"

# 3. Remove any prior marker
rm -f "$BASE/.env-audit.passed"

# 4. Provision clean-subshell verification runner
cat << 'VERIFY_EOF' > "$BASE/verify-env"
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

bash -n config/profile.env || { echo "FAIL: Syntax error in config/profile.env." >&2; exit 1; }

OUTPUT=$(env -i HOME="$HOME" USER="${USER:-learner}" PATH="/usr/bin:/bin" bash --norc --noprofile -c "
  . \"$(pwd)/config/profile.env\"
  [ \"\${APP_REGION:-}\" = \"us-east-1\" ] || { echo 'BAD_REGION'; exit 1; }
  [ \"\${SERVICE_TIER:-}\" = \"critical\" ] || { echo 'BAD_TIER'; exit 1; }
  type -P svc-ctl >/dev/null || { echo 'SVC_NOT_FOUND'; exit 1; }
  svc-ctl
" 2>&1) || {
  echo "FAIL: Clean subshell execution failed: $OUTPUT" >&2
  exit 1
}

if [ "$OUTPUT" != "SVC-CTL-OK" ]; then
  echo "FAIL: Unexpected output from clean subshell test: $OUTPUT" >&2
  exit 1
fi

cat << 'MARKER' > .env-audit.passed
{"status": "PASSED", "audit": "shell-environment-variables"}
MARKER
echo "SUCCESS: Shell environment variables and PATH resolution verified."
exit 0
VERIFY_EOF
chmod 0755 "$BASE/verify-env"
