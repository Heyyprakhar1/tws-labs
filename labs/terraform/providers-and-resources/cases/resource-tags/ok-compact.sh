printf 'resource "aws_s3_bucket" "app_assets" {\nbucket = "example-app-assets-sandbox"\ntags={\nEnvironment="production"\nTeam="platform"\n}\n}\n' > infra/main.tf
