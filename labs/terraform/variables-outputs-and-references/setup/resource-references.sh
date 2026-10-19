mkdir -p "$LAB_HOME/infra"
printf 'variable "environment" {\n  type    = string\n  default = "dev"\n}\n' > "$LAB_HOME/infra/variables.tf"
cat > "$LAB_HOME/infra/main.tf" << 'EOF'
resource "aws_s3_bucket" "app_assets" {
  bucket = "example-app-assets-sandbox"

  tags = {
    Environment = var.environment
    Team        = "platform"
  }
}
EOF
