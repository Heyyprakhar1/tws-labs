mkdir -p "$LAB_HOME/infra"
[ -f "$LAB_HOME/serial.txt" ] || echo 7 > "$LAB_HOME/serial.txt"
[ -f "$LAB_HOME/.gitignore" ] || printf '*.tfstate\n*.tfstate.*\n*.tfvars\n' > "$LAB_HOME/.gitignore"
