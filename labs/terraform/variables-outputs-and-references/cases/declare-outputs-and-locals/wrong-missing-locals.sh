printf '' > infra/locals.tf
printf 'output "bucket_arn" {\n  description = "The ARN of the S3 bucket"\n  value       = aws_s3_bucket.app_assets.arn\n}\n' > infra/outputs.tf
