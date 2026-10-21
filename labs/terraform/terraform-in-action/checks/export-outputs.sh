. "$LAB_LIB"
[ -f infra/outputs.tf ] || fail "infra/outputs.tf does not exist yet."
id=$(hcl_strip infra/outputs.tf | hcl_block 'output[[:space:]]+"bucket_id"') || fail 'infra/outputs.tf has no output "bucket_id".'
[ "$(printf '%s\n' "$id" | hcl_attr value)" = 'aws_s3_bucket.app.id' ] || fail "bucket_id should expose the id of the app bucket."
arn=$(hcl_strip infra/outputs.tf | hcl_block 'output[[:space:]]+"bucket_arn"') || fail 'infra/outputs.tf has no output "bucket_arn".'
[ "$(printf '%s\n' "$arn" | hcl_attr value)" = 'aws_s3_bucket.app.arn' ] || fail "bucket_arn should expose the arn of the app bucket."
