printf 'output "bucket_arn" {\n  value = aws_s3_bucket.app.arn\n}\n' > infra/outputs.tf
