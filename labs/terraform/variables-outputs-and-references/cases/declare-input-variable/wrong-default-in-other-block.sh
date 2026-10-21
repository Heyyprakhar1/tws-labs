printf 'variable "environment" {\n  type = string\n  description = "Target deployment environment"\n}\n\nvariable "region" {\n  default = "dev"\n}\n' > infra/variables.tf
