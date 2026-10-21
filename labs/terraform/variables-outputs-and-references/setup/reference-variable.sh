mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/infra/variables.tf" ] || printf 'variable "environment" {\n  type        = string\n  description = "Target deployment environment"\n  default     = "dev"\n}\n' > "$LAB_HOME/infra/variables.tf"
