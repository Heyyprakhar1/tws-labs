mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/infra/providers.tf" ] || printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    aws = {\n      source  = "hashicorp/aws"\n      version = "~> 5.0"\n    }\n  }\n}\n\nprovider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
