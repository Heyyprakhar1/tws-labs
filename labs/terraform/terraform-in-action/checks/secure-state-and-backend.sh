. "$LAB_LIB"
[ -f infra/backend.tf ] || fail "infra/backend.tf does not exist."
b=$(hcl_strip infra/backend.tf | hcl_block 'terraform' | hcl_block 'backend[[:space:]]+"s3"') || fail 'infra/backend.tf lost its backend "s3" block.'
[ "$(printf '%s\n' "$b" | hcl_attr use_lockfile)" = 'true' ] || fail "The s3 backend is still unlocked: concurrent applies could corrupt state."
[ -f .gitignore ] || fail ".gitignore does not exist yet."
ignore_has .gitignore '*.tfstate' || fail ".gitignore does not ignore Terraform state files yet."
ignore_has .gitignore '*.tfstate.*' || fail ".gitignore does not ignore state backups yet."
ignore_has .gitignore '*.tfvars' || fail ".gitignore does not ignore variable files yet."
