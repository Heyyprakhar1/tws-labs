printf 'terraform {\n  backend "s3" {\n    bucket       = "example-state-storage"\n    key          = "app/terraform.tfstate"\n    region       = "us-east-1"\n    use_lockfile = true # native S3 locking\n  }\n}\n' > infra/backend.tf
printf '# Terraform state\n*.tfstate\n*.tfstate.*\n# secrets\n*.tfvars\n' > .gitignore
