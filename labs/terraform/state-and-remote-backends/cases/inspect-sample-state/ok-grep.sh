grep -o '"serial":[[:space:]]*[0-9]*' sample/terraform.tfstate | cut -d: -f2 | tr -d ' ' > serial.txt
