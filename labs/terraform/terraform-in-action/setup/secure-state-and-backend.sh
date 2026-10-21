mkdir -p "$LAB_HOME/infra"
# the lab starts with a broken providers.tf (region typo): a skipped repair-providers task gets the repaired file
if [ ! -f "$LAB_HOME/infra/providers.tf" ] || grep -q 'us-east1' "$LAB_HOME/infra/providers.tf"; then
  printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    aws = {\n      source = "hashicorp/aws"\n    }\n  }\n}\n\nprovider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
fi
[ -f "$LAB_HOME/infra/variables.tf" ] || printf 'variable "environment" {\n  type    = string\n  default = "dev"\n}\n' > "$LAB_HOME/infra/variables.tf"
# the lab starts with a hard-coded Environment tag: a skipped parameterize-resources task gets the variable version
sed -i 's|Environment[[:space:]]*=[[:space:]]*"dev"|Environment = var.environment|' "$LAB_HOME/infra/main.tf"
[ -f "$LAB_HOME/infra/outputs.tf" ] || printf 'output "bucket_id" {\n  value = aws_s3_bucket.app.id\n}\n\noutput "bucket_arn" {\n  value = aws_s3_bucket.app.arn\n}\n' > "$LAB_HOME/infra/outputs.tf"
[ -f "$LAB_HOME/infra/backend.tf" ] || cat > "$LAB_HOME/infra/backend.tf" << 'EOF'
terraform {
  backend "s3" {
    bucket = "example-state-storage"
    key    = "app/terraform.tfstate"
    region = "us-east-1"
  }
}
EOF
