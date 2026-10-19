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
