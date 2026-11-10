. "$LAB_LIB"

resolved=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" bash --norc --noprofile -c ". \"$HOME/env-incident/config/profile.env\" && type -P svc-ctl" 2>/dev/null || true)
[ "$resolved" = "$HOME/env-incident/bin/svc-ctl" ] || fail "PATH does not resolve svc-ctl when profile is sourced in a clean shell."
