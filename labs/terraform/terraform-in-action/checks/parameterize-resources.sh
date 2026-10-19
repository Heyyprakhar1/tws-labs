. "$LAB_LIB"
v=infra/variables.tf
[ -f "$v" ] || v="$LAB_HOME/infra/variables.tf"
[ -f "$v" ] || fail "infra/variables.tf does not exist."
grep -Eq 'variable[[:space:]]+["'\'']environment["'\''][[:space:]]*\{' "$v" || fail 'Declare variable "environment" in infra/variables.tf.'
grep -Eq 'type[[:space:]]*=[[:space:]]*string' "$v" || fail 'Set type = string in infra/variables.tf.'
grep -Eq 'default[[:space:]]*=[[:space:]]*["'\'']dev["'\'']' "$v" || fail 'Set default = "dev" in infra/variables.tf.'

m=infra/main.tf
[ -f "$m" ] || m="$LAB_HOME/infra/main.tf"
[ -f "$m" ] || fail "infra/main.tf does not exist."
grep -Eq 'Environment[[:space:]]*=[[:space:]]*var\.environment' "$m" || fail 'Set Environment = var.environment in infra/main.tf.'
