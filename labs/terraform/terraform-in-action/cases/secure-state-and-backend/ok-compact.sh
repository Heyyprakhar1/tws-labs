printf 'terraform {\n  backend "s3" {\n    bucket       = "example-state-storage"\n    key          = "app/terraform.tfstate"\n    region       = "us-east-1"\n    use_lockfile=true\n  }\n}\n' > infra/backend.tf
printf '*.tfstate\n*.tfstate.*\n*.tfvars\n.terraform/\n' > .gitignore
