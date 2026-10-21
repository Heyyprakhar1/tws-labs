mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/infra/variables.tf" ] || printf 'variable "environment" {\n  type        = string\n  description = "Target deployment environment"\n  default     = "dev"\n}\n' > "$LAB_HOME/infra/variables.tf"
[ -f "$LAB_HOME/infra/main.tf" ] || cat > "$LAB_HOME/infra/main.tf" << 'EOF'
resource "aws_s3_bucket" "app_assets" {
  bucket = "example-app-assets-sandbox"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
EOF
# the earlier task changed the Environment tag to read the variable: do it here if it was skipped
sed -i 's|Environment[[:space:]]*=[[:space:]]*"production"|Environment = var.environment|' "$LAB_HOME/infra/main.tf"
grep -qs 'assets_versioning' "$LAB_HOME/infra/main.tf" || cat >> "$LAB_HOME/infra/main.tf" << 'EOF'

resource "aws_s3_bucket_versioning" "assets_versioning" {
  bucket = aws_s3_bucket.app_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}
EOF
