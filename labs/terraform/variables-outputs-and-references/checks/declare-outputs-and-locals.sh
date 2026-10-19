. "$LAB_LIB"
l=infra/locals.tf
[ -f "$l" ] || l="$LAB_HOME/infra/locals.tf"
[ -f "$l" ] || fail "infra/locals.tf does not exist."
grep -Eq 'locals[[:space:]]*\{' "$l" || fail "infra/locals.tf needs a locals { ... } block."
grep -Eq 'ManagedBy[[:space:]]*=[[:space:]]*["'\'']terraform["'\'']' "$l" || fail 'Set ManagedBy = "terraform" inside locals.'

o=infra/outputs.tf
[ -f "$o" ] || o="$LAB_HOME/infra/outputs.tf"
[ -f "$o" ] || fail "infra/outputs.tf does not exist."
grep -Eq 'output[[:space:]]+["'\'']bucket_arn["'\''][[:space:]]*\{' "$o" || fail 'Declare output "bucket_arn" in infra/outputs.tf.'
grep -Eq 'value[[:space:]]*=[[:space:]]*aws_s3_bucket\.app_assets\.arn' "$o" || fail 'Set value = aws_s3_bucket.app_assets.arn inside output "bucket_arn".'
