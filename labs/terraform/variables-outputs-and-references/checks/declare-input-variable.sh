. "$LAB_LIB"
f=infra/variables.tf
[ -f "$f" ] || f="$LAB_HOME/infra/variables.tf"
[ -f "$f" ] || fail "infra/variables.tf does not exist."
grep -Eq 'variable[[:space:]]+["'\'']environment["'\''][[:space:]]*\{' "$f" || fail 'Declare variable "environment" in infra/variables.tf.'
grep -Eq 'type[[:space:]]*=[[:space:]]*string' "$f" || fail 'Set type = string inside variable "environment".'
grep -Eq 'default[[:space:]]*=[[:space:]]*["'\'']dev["'\'']' "$f" || fail 'Set default = "dev" inside variable "environment".'
