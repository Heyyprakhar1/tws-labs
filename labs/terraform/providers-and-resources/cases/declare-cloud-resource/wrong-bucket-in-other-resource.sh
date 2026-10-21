printf 'resource "aws_s3_bucket" "app_assets" {\n}\n\nresource "aws_s3_bucket" "logs" {\n  bucket = "example-app-assets-sandbox"\n}\n' > infra/main.tf
