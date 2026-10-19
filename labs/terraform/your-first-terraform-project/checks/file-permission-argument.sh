. "$LAB_LIB"
f=main.tf
[ -f "$f" ] || f="$LAB_HOME/infra/main.tf"
[ -f "$f" ] || fail "main.tf does not exist."
grep -Eq 'file_permission[[:space:]]*=[[:space:]]*["'\'']0?644["'\'']' "$f" || fail 'Set file_permission = "0644" inside resource "local_file" "welcome".'
