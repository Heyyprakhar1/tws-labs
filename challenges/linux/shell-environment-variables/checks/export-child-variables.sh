. "$LAB_LIB"

vars=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" bash --norc --noprofile -c ". \"$HOME/env-incident/config/profile.env\" && env" 2>/dev/null || true)
echo "$vars" | grep -q "^APP_ENV=production$" || fail "APP_ENV=production is not exported to child processes."
echo "$vars" | grep -q "^DB_PORT=5432$" || fail "DB_PORT=5432 is not exported to child processes."
