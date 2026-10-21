. "$LAB_LIB"
[ -f infra/main.tf ] || fail "infra/main.tf does not exist yet."
res=$(hcl_strip infra/main.tf | hcl_block 'resource[[:space:]]+"aws_s3_bucket"[[:space:]]+"app_assets"') || fail "infra/main.tf has no aws_s3_bucket resource named app_assets."
[ "$(printf '%s\n' "$res" | hcl_attr bucket)" = '"example-app-assets-sandbox"' ] || fail "Set the bucket argument to the sandbox name from the task."
