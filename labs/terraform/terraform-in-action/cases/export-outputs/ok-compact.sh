printf 'output "bucket_id"{\nvalue=aws_s3_bucket.app.id\n}\noutput "bucket_arn"{\nvalue=aws_s3_bucket.app.arn\n}\n' > infra/outputs.tf
