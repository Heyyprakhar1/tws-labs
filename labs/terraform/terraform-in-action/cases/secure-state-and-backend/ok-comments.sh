sed -i '/backend "s3" {/a \  use_lockfile = true' infra/backend.tf
printf '# Terraform state files\n*.tfstate\n*.tfstate.*\n*.tfvars\n' > .gitignore
