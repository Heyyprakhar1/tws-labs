printf 'terraform{\nrequired_providers{\naws={\nsource="hashicorp/aws"\n}\n}\n}\nprovider "aws"{\nregion="us-east-1"\n}\n' > infra/providers.tf
