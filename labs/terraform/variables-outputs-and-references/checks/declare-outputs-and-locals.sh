. "$LAB_LIB"
[ -f infra/locals.tf ] || fail "infra/locals.tf does not exist yet."
tags=$(hcl_strip infra/locals.tf | hcl_block 'locals' | hcl_block 'common_tags[[:space:]]*=') || fail "infra/locals.tf needs a locals block with a common_tags map."
[ "$(printf '%s\n' "$tags" | hcl_attr ManagedBy)" = '"terraform"' ] || fail "common_tags needs ManagedBy set to terraform."
[ -f infra/outputs.tf ] || fail "infra/outputs.tf does not exist yet."
out=$(hcl_strip infra/outputs.tf | hcl_block 'output[[:space:]]+"bucket_arn"') || fail 'infra/outputs.tf has no output "bucket_arn".'
[ "$(printf '%s\n' "$out" | hcl_attr description)" = '"TheARNoftheS3bucket"' ] || fail "Describe the output with the description from the task."
[ "$(printf '%s\n' "$out" | hcl_attr value)" = 'aws_s3_bucket.app_assets.arn' ] || fail "The output should expose the arn attribute of the app_assets bucket."
