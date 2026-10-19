printf 'variable "environment" {\n  type = string\n  default = "dev"\n}\n' > infra/variables.tf
sed -i 's|Environment[[:space:]]*=[[:space:]]*"dev"|Environment=var.environment|' infra/main.tf
