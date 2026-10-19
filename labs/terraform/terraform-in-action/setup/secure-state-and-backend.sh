mkdir -p "$LAB_HOME/infra"
printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    aws = {\n      source = "hashicorp/aws"\n    }\n  }\n}\n\nprovider "aws" {\n  region = "us-east-1"\n}\n' > "$LAB_HOME/infra/providers.tf"
printf 'variable "environment" {\n  type    = string\n  default = "dev"\n}\n' > "$LAB_HOME/infra/variables.tf"
cat > "$LAB_HOME/infra/main.tf" << 'EOF'
resource "aws_s3_bucket" "app" {
  bucket = "example-service-storage-dev"

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
EOF
printf 'output "bucket_id" {\n  value = aws_s3_bucket.app.id\n}\n\noutput "bucket_arn" {\n  value = aws_s3_bucket.app.arn\n}\n' > "$LAB_HOME/infra/outputs.tf"
cat > "$LAB_HOME/infra/backend.tf" << 'EOF'
terraform {
  backend "s3" {
    bucket = "example-state-storage"
    key    = "app/terraform.tfstate"
    region = "us-east-1"
  }
}
EOF
rm -f "$LAB_HOME/.gitignore"
