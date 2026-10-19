printf 'output "bucket_id" {\n  value = aws_s3_bucket.app.id\n}\n' > infra/outputs.tf
