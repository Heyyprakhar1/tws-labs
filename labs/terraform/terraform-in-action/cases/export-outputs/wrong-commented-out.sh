printf '# output "bucket_id" {\n#   value = aws_s3_bucket.app.id\n# }\n# \n# output "bucket_arn" {\n#   value = aws_s3_bucket.app.arn\n# }\n' > infra/outputs.tf
