. "$LAB_LIB"
f=infra/main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || f=main.tf
[ -f "$f" ] || fail "infra/main.tf does not exist."
grep -Eq 'tags[[:space:]]*=[[:space:]]*\{' "$f" || fail "Add a tags = { ... } map inside the resource block."
grep -Eq 'Environment[[:space:]]*=[[:space:]]*["'\'']production["'\'']' "$f" || fail 'Set Environment = "production" inside the tags map.'
grep -Eq 'Team[[:space:]]*=[[:space:]]*["'\'']platform["'\'']' "$f" || fail 'Set Team = "platform" inside the tags map.'
