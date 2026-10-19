sed -i 's|Environment[[:space:]]*=[[:space:]]*"production"|Environment = "var.environment"|' infra/main.tf
