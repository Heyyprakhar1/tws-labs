printf 'terraform {\n  backend "s3" {\n    bucket = "example-corp-tfstate"\n    key    = "services/app/terraform.tfstate"\n    region = "eu-west-1"\n  }\n}\n' > infra/backend.tf
