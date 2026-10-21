mkdir -p "$LAB_HOME/infra"
# the lab starts with a broken providers.tf (region typo): a skipped repair-providers task gets the repaired file
if [ ! -f "$LAB_HOME/infra/providers.tf" ] || grep -q 'us-east1' "$LAB_HOME/infra/providers.tf"; then
  printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    aws = {\n      source = "hashicorp/aws"\n    }\n  }\n}\n\nprovider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
fi
