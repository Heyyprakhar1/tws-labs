. "$LAB_LIB"
f=infra/providers.tf
[ -f "$f" ] || f="$LAB_HOME/infra/providers.tf"
[ -f "$f" ] || f=providers.tf
[ -f "$f" ] || fail "infra/providers.tf does not exist."
grep -Eq 'provider[[:space:]]+["'\'']aws["'\''][[:space:]]*\{' "$f" || fail 'infra/providers.tf needs a provider "aws" { ... } block.'
grep -Eq 'region[[:space:]]*=[[:space:]]*["'\'']us-east-1["'\'']' "$f" || fail 'Set region = "us-east-1" inside the aws provider block.'
