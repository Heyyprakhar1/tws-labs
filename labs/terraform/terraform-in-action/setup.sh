mkdir -p infra

# Seed a broken providers.tf with region typo and missing required_providers
cat > infra/providers.tf << 'EOF'
provider "aws" {
  region = "us-east1"
}
EOF

# Seed main.tf with hardcoded environment tag
cat > infra/main.tf << 'EOF'
resource "aws_s3_bucket" "app" {
  bucket = "example-service-storage-dev"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
EOF

# Seed backend.tf without state locking
cat > infra/backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket = "example-state-storage"
    key    = "app/terraform.tfstate"
    region = "us-east-1"
  }
}
EOF

rm -f infra/variables.tf infra/outputs.tf .gitignore
