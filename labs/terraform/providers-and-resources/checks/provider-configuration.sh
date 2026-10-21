. "$LAB_LIB"
[ -f infra/providers.tf ] || fail "infra/providers.tf does not exist yet."
p=$(hcl_strip infra/providers.tf | hcl_block 'provider[[:space:]]+"aws"') || fail 'infra/providers.tf has no provider "aws" block.'
[ "$(printf '%s\n' "$p" | hcl_attr region)" = '"us-east-1"' ] || fail "The aws provider needs its region set to us-east-1."
