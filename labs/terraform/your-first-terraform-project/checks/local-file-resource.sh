. "$LAB_LIB"
f=main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || fail "main.tf does not exist."
grep -Eq 'resource[[:space:]]+["'\'']local_file["'\''][[:space:]]+["'\'']welcome["'\''][[:space:]]*\{' "$f" || fail 'Declare resource "local_file" "welcome" in main.tf.'
grep -Eq 'filename[[:space:]]*=[[:space:]]*["'\'']welcome\.txt["'\'']' "$f" || fail 'Set filename = "welcome.txt" inside the resource block.'
grep -Eq 'content[[:space:]]*=[[:space:]]*["'\'']Infrastructure as Code with Terraform["'\'']' "$f" || fail 'Set content = "Infrastructure as Code with Terraform".'
