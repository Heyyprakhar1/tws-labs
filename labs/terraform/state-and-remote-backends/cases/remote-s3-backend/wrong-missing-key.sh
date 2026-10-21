printf 'terraform {\n  backend "s3" {\n    bucket = "example-corp-tfstate"\n    region = "us-east-1"\n  }\n}\n' > infra/backend.tf
