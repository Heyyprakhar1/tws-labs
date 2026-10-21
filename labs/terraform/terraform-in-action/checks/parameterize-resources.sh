. "$LAB_LIB"
[ -f infra/variables.tf ] || fail "infra/variables.tf does not exist yet."
v=$(hcl_strip infra/variables.tf | hcl_block 'variable[[:space:]]+"environment"') || fail 'infra/variables.tf has no variable "environment".'
[ "$(printf '%s\n' "$v" | hcl_attr type)" = 'string' ] || fail "The variable should have type string."
[ "$(printf '%s\n' "$v" | hcl_attr default)" = '"dev"' ] || fail "The variable should default to the value that used to be hard-coded."
[ -f infra/main.tf ] || fail "infra/main.tf does not exist."
res=$(hcl_strip infra/main.tf | hcl_block 'resource[[:space:]]+"aws_s3_bucket"[[:space:]]+"app"') || fail "infra/main.tf lost its aws_s3_bucket resource named app."
tags=$(printf '%s\n' "$res" | hcl_block 'tags[[:space:]]*=') || fail "The app bucket lost its tags map."
[ "$(printf '%s\n' "$tags" | hcl_attr Environment)" = 'var.environment' ] || fail "The Environment tag still has a fixed value instead of reading the variable."
