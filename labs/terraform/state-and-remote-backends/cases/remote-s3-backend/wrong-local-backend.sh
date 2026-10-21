printf 'terraform {\n  backend "local" {\n    bucket = "example-corp-tfstate"\n    key    = "services/app/terraform.tfstate"\n    region = "us-east-1"\n  }\n}\n' > infra/backend.tf
