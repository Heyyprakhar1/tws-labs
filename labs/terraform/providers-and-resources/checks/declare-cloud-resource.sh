. "$LAB_LIB"
f=infra/main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || f=main.tf
[ -f "$f" ] || fail "infra/main.tf does not exist."
grep -Eq 'resource[[:space:]]+["'\'']aws_s3_bucket["'\''][[:space:]]+["'\'']app_assets["'\''][[:space:]]*\{' "$f" || fail 'Declare resource "aws_s3_bucket" "app_assets" in infra/main.tf.'
grep -Eq 'bucket[[:space:]]*=[[:space:]]*["'\'']example-app-assets-sandbox["'\'']' "$f" || fail 'Set bucket = "example-app-assets-sandbox" inside the resource block.'
