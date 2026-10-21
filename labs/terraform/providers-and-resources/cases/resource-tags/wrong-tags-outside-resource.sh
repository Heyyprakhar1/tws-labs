printf 'resource "aws_s3_bucket" "app_assets" {\n  bucket = "example-app-assets-sandbox"\n}\n\ntags = {\n  Environment = "production"\n  Team        = "platform"\n}\n' > infra/main.tf
