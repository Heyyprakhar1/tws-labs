mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/serial.txt" ] || echo 7 > "$LAB_HOME/serial.txt"
[ -f "$LAB_HOME/.gitignore" ] || printf '*.tfstate\n*.tfstate.*\n*.tfvars\n' > "$LAB_HOME/.gitignore"
[ -f "$LAB_HOME/infra/backend.tf" ] || printf 'terraform {\n  backend "s3" {\n    bucket = "example-corp-tfstate"\n    key    = "services/app/terraform.tfstate"\n    region = "us-east-1"\n  }\n}\n' > "$LAB_HOME/infra/backend.tf"
