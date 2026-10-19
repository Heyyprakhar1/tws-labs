. "$LAB_LIB"
f=serial.txt
[ -f "$f" ] || f="$LAB_HOME/serial.txt"
[ -f "$f" ] || fail "serial.txt does not exist."
val=$(tr -d '[:space:]' < "$f")
[ "$val" = "7" ] || fail "serial.txt should contain 7 (the serial value from sample/terraform.tfstate)."
