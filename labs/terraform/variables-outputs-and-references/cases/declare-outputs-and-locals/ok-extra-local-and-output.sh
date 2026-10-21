printf 'locals {\n  prefix = "app"\n\n  common_tags = {\n    ManagedBy = "terraform"\n  }\n}\n' > infra/locals.tf
printf 'output "bucket_id" {\n  value = aws_s3_bucket.app_assets.id\n}\n\noutput "bucket_arn" {\n  description = "The ARN of the S3 bucket"\n  value       = aws_s3_bucket.app_assets.arn\n}\n' > infra/outputs.tf
