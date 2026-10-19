mkdir -p infra
cat > infra/providers.tf << 'EOF'
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
EOF

cat > infra/main.tf << 'EOF'
resource "aws_s3_bucket" "app_assets" {
  bucket = "example-app-assets-sandbox"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
EOF
rm -f infra/variables.tf infra/locals.tf infra/outputs.tf
