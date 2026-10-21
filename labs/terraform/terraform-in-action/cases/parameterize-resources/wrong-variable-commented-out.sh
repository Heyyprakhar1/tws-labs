printf '# variable "environment" {\n#   type    = string\n#   default = "dev"\n# }\n' > infra/variables.tf
printf 'resource "aws_s3_bucket" "app" {\n  bucket = "example-service-storage-dev"\n\n  tags = {\n    Environment = var.environment\n    ManagedBy   = "terraform"\n  }\n}\n' > infra/main.tf
