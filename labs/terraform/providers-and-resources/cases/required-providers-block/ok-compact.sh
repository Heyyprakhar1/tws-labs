printf 'terraform{\nrequired_version=">=1.10.0"\nrequired_providers{\naws={\nsource="hashicorp/aws"\nversion="~>5.0"\n}\n}\n}\nprovider "aws" {\n  region = "us-east-1"\n}\n' > infra/providers.tf
