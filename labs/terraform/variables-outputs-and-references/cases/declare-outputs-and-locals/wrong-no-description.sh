printf 'locals {\n  common_tags = {\n    ManagedBy = "terraform"\n  }\n}\n' > infra/locals.tf
printf 'output "bucket_arn" {\n  value       = aws_s3_bucket.app_assets.arn\n}\n' > infra/outputs.tf
