. "$LAB_LIB"
[ -f infra/providers.tf ] || fail "infra/providers.tf does not exist."
p=$(hcl_strip infra/providers.tf | hcl_block 'provider[[:space:]]+"aws"') || fail 'infra/providers.tf has no provider "aws" block.'
[ "$(printf '%s\n' "$p" | hcl_attr region)" = '"us-east-1"' ] || fail "The aws provider's region is not a valid AWS region yet."
aws=$(hcl_strip infra/providers.tf | hcl_block 'terraform' | hcl_block 'required_providers' | hcl_block 'aws[[:space:]]*=') || fail "Add a terraform block that declares the aws provider under required_providers."
[ "$(printf '%s\n' "$aws" | hcl_attr source)" = '"hashicorp/aws"' ] || fail "The aws provider should come from the hashicorp namespace."
