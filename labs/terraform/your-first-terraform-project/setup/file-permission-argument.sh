# cwd: infra
mkdir -p "$LAB_HOME/infra"
grep -qs 'local_file' "$LAB_HOME/infra/main.tf" || printf 'terraform {\n  required_version = ">= 1.10.0"\n\n  required_providers {\n    local = {\n      source  = "hashicorp/local"\n      version = "~> 2.5"\n    }\n  }\n}\n\nresource "local_file" "welcome" {\n  filename = "welcome.txt"\n  content  = "Infrastructure as Code with Terraform"\n}\n' > "$LAB_HOME/infra/main.tf"
