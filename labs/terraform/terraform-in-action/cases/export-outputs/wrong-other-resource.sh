printf 'output "bucket_id" {\n  value = aws_s3_bucket.logs.id\n}\n\noutput "bucket_arn" {\n  value = aws_s3_bucket.logs.arn\n}\n' > infra/outputs.tf
