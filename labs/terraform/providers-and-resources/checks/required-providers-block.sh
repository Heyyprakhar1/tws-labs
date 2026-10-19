. "$LAB_LIB"
f=infra/providers.tf
[ -f "$f" ] || f="$LAB_HOME/infra/providers.tf"
[ -f "$f" ] || f=providers.tf
[ -f "$f" ] || fail "infra/providers.tf does not exist."
grep -Eq 'required_providers[[:space:]]*\{' "$f" || fail "Add a required_providers { ... } block inside terraform {}."
grep -Eq 'source[[:space:]]*=[[:space:]]*["'\'']hashicorp/aws["'\'']' "$f" || fail 'Set source = "hashicorp/aws" for the aws provider.'
grep -Eq 'version[[:space:]]*=[[:space:]]*["'\''][~>=<[:space:]]*5(\.[0-9]+)?["'\'']' "$f" || fail 'Set version = "~> 5.0" for the aws provider.'
