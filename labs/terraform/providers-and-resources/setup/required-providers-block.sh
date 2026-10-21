mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/infra/providers.tf" ] || printf 'provider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
