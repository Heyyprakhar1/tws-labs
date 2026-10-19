printf 'terraform {\n  required_version = ">= 1.5.0"\n}\n\nresource "local_file" "welcome" {\n  filename = "welcome.txt"\n  content  = "Infrastructure as Code with Terraform"\n}\n' > main.tf
