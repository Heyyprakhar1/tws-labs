printf 'terraform {\n  required_providers {\n    aws = {\n      source = "aws"\n    }\n  }\n}\n\nprovider "aws" {\n  region = "us-east-1"\n}\n' > infra/providers.tf
