printf 'resource "aws_s3_bucket" "logs" {\n  bucket = "example-logs-sandbox"\n}\n\nresource "aws_s3_bucket" "app_assets" {\n  bucket = "example-app-assets-sandbox"\n}\n' > infra/main.tf
