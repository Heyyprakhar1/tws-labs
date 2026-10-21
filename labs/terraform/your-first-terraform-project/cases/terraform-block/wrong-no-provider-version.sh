printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    local = {\n      source  = "hashicorp/local"\n    }\n  }\n}\n' > main.tf
