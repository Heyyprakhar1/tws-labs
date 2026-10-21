printf 'terraform {\n  backend "s3" {\n    bucket = "my-state"\n    key    = "services/app/terraform.tfstate"\n    region = "us-east-1"\n  }\n}\n' > infra/backend.tf
