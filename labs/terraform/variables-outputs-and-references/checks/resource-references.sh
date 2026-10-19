. "$LAB_LIB"
f=infra/main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || fail "infra/main.tf does not exist."
grep -Eq 'resource[[:space:]]+["'\'']aws_s3_bucket_versioning["'\''][[:space:]]+["'\'']assets_versioning["'\''][[:space:]]*\{' "$f" || fail 'Declare resource "aws_s3_bucket_versioning" "assets_versioning" in infra/main.tf.'
grep -Eq 'bucket[[:space:]]*=[[:space:]]*aws_s3_bucket\.app_assets\.id' "$f" || fail 'Reference bucket = aws_s3_bucket.app_assets.id inside the versioning resource.'
grep -Eq 'status[[:space:]]*=[[:space:]]*["'\'']Enabled["'\'']' "$f" || fail 'Set status = "Enabled" inside versioning_configuration.'
