. "$LAB_LIB"

# 1. Syntax check
bash -n env-incident/config/profile.env 2>/dev/null || fail "Syntax error in env-incident/config/profile.env."

# 2. Source and inspect assigned values in clean subshell
vals=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" bash --norc --noprofile -c '
  . "$HOME/env-incident/config/profile.env"
  echo "REGION=${APP_REGION:-}"
  echo "TIER=${SERVICE_TIER:-}"
' 2>/dev/null || true)

echo "$vals" | grep -q "^REGION=us-east-1$" || fail "APP_REGION is not set to us-east-1 in profile.env."
echo "$vals" | grep -q "^TIER=critical$" || fail "SERVICE_TIER is not set to critical in profile.env."
