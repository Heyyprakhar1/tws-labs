. "$LAB_LIB"
f=main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || fail "main.tf does not exist."
grep -Eq 'terraform[[:space:]]*\{' "$f" || fail "main.tf needs a terraform { ... } block."
grep -Eq 'required_version[[:space:]]*=[[:space:]]*["]>=[[:space:]]*1\.10\.0["]' "$f" || fail 'Set required_version = ">= 1.10.0" inside the terraform block.'
grep -Eq 'source[[:space:]]*=[[:space:]]*["'\'']hashicorp/local["'\'']' "$f" || fail 'Declare source = "hashicorp/local" inside required_providers.'
