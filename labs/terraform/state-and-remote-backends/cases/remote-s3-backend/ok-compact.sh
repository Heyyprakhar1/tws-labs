printf 'terraform{\nbackend "s3"{\nbucket="example-corp-tfstate"\nkey="services/app/terraform.tfstate"\nregion="us-east-1"\n}\n}\n' > infra/backend.tf
