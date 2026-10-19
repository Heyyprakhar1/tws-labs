. "$LAB_LIB"
f=infra/providers.tf
[ -f "$f" ] || f="$LAB_HOME/infra/providers.tf"
[ -f "$f" ] || fail "infra/providers.tf does not exist."
grep -Eq 'region[[:space:]]*=[[:space:]]*["'\'']us-east-1["'\'']' "$f" || fail 'Correct region to "us-east-1" in infra/providers.tf.'
grep -Eq 'source[[:space:]]*=[[:space:]]*["'\'']hashicorp/aws["'\'']' "$f" || fail 'Add source = "hashicorp/aws" inside required_providers in infra/providers.tf.'
