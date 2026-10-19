printf '\nresource "aws_s3_bucket_versioning" "assets_versioning" {\n  bucket = "aws_s3_bucket.app_assets.id"\n  versioning_configuration {\n    status = "Enabled"\n  }\n}\n' >> infra/main.tf
