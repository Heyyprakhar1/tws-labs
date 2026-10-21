printf 'terraform {\n  backend "s3" {\n  }\n}\n\nlocals {\n  bucket = "example-corp-tfstate"\n  key    = "services/app/terraform.tfstate"\n  region = "us-east-1"\n}\n' > infra/backend.tf
