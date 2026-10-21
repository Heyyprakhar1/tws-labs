# cwd: infra
mkdir -p "$LAB_HOME/infra"
grep -qs 'required_providers' "$LAB_HOME/infra/main.tf" || printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    local = {\n      source  = "hashicorp/local"\n      version = "~> 2.5"\n    }\n  }\n}\n' > "$LAB_HOME/infra/main.tf"
