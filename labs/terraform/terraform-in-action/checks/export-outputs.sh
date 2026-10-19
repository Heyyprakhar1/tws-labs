. "$LAB_LIB"
f=infra/outputs.tf
[ -f "$f" ] || f="$LAB_HOME/infra/outputs.tf"
[ -f "$f" ] || fail "infra/outputs.tf does not exist."
grep -Eq 'output[[:space:]]+["'\'']bucket_id["'\''][[:space:]]*\{' "$f" || fail 'Declare output "bucket_id" in infra/outputs.tf.'
grep -Eq 'value[[:space:]]*=[[:space:]]*aws_s3_bucket\.app\.id' "$f" || fail 'Set value = aws_s3_bucket.app.id inside output "bucket_id".'
grep -Eq 'output[[:space:]]+["'\'']bucket_arn["'\''][[:space:]]*\{' "$f" || fail 'Declare output "bucket_arn" in infra/outputs.tf.'
grep -Eq 'value[[:space:]]*=[[:space:]]*aws_s3_bucket\.app\.arn' "$f" || fail 'Set value = aws_s3_bucket.app.arn inside output "bucket_arn".'
