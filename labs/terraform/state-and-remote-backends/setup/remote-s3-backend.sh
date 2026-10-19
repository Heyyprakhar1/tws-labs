mkdir -p "$LAB_HOME/infra"
echo 7 > "$LAB_HOME/serial.txt"
printf '*.tfstate\n*.tfstate.*\n*.tfvars\n' > "$LAB_HOME/.gitignore"
