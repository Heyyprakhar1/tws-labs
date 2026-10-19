mkdir -p "$LAB_HOME/infra"
printf 'provider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
