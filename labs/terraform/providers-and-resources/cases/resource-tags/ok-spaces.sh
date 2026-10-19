printf 'resource "aws_s3_bucket" "app_assets" {\n  bucket = "example-app-assets-sandbox"\n  tags = { Environment="production", Team="platform" }\n}\n' > infra/main.tf
