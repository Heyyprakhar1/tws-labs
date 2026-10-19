. "$LAB_LIB"
f=infra/backend.tf
[ -f "$f" ] || f="$LAB_HOME/infra/backend.tf"
[ -f "$f" ] || f=backend.tf
[ -f "$f" ] || fail "infra/backend.tf does not exist."
grep -Eq 'backend[[:space:]]+["'\'']s3["'\''][[:space:]]*\{' "$f" || fail 'infra/backend.tf needs a backend "s3" { ... } block.'
grep -Eq 'bucket[[:space:]]*=[[:space:]]*["'\'']example-corp-tfstate["'\'']' "$f" || fail 'Set bucket = "example-corp-tfstate" inside backend "s3".'
grep -Eq 'key[[:space:]]*=[[:space:]]*["'\'']services/app/terraform\.tfstate["'\'']' "$f" || fail 'Set key = "services/app/terraform.tfstate" inside backend "s3".'
grep -Eq 'region[[:space:]]*=[[:space:]]*["'\'']us-east-1["'\'']' "$f" || fail 'Set region = "us-east-1" inside backend "s3".'
