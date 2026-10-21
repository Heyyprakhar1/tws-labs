. "$LAB_LIB"
[ -f infra/backend.tf ] || fail "infra/backend.tf does not exist yet."
b=$(hcl_strip infra/backend.tf | hcl_block 'terraform' | hcl_block 'backend[[:space:]]+"s3"') || fail 'infra/backend.tf lost its backend "s3" block.'
[ "$(printf '%s\n' "$b" | hcl_attr use_lockfile)" = 'true' ] || fail "Turn on native locking inside the s3 backend block."
