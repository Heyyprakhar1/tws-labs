. "$LAB_LIB"
[ -f infra/backend.tf ] || fail "infra/backend.tf does not exist yet."
b=$(hcl_strip infra/backend.tf | hcl_block 'terraform' | hcl_block 'backend[[:space:]]+"s3"') || fail 'infra/backend.tf needs a terraform block containing backend "s3".'
[ "$(printf '%s\n' "$b" | hcl_attr bucket)" = '"example-corp-tfstate"' ] || fail "The backend needs the state bucket name from the task."
[ "$(printf '%s\n' "$b" | hcl_attr key)" = '"services/app/terraform.tfstate"' ] || fail "The backend needs the state key (path) from the task."
[ "$(printf '%s\n' "$b" | hcl_attr region)" = '"us-east-1"' ] || fail "The backend needs the bucket's region."
