. "$LAB_LIB"
f=infra/main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || fail "infra/main.tf does not exist."
grep -Eq 'Environment[[:space:]]*=[[:space:]]*var\.environment' "$f" || fail 'Set Environment = var.environment inside tags in infra/main.tf.'
