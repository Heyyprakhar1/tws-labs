printf 'locals{\ncommon_tags={\nManagedBy="terraform"\n}\n}\n' > infra/locals.tf
printf 'output "bucket_arn" {\ndescription="The ARN of the S3 bucket"\nvalue=aws_s3_bucket.app_assets.arn\n}\n' > infra/outputs.tf
