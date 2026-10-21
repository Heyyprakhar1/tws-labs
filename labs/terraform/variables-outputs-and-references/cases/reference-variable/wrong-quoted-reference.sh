printf 'resource "aws_s3_bucket" "app_assets" {\n  bucket = "example-app-assets-sandbox"\n\n  tags = {\n    Environment = "var.environment"\n    Team        = "platform"\n  }\n}\n' > infra/main.tf
