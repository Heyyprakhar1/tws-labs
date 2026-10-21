. "$LAB_LIB"
[ -f sample/terraform.tfstate ] || fail "sample/terraform.tfstate is missing: restart the lab."
want=$(sed -n 's/^[[:space:]]*"serial"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' sample/terraform.tfstate | head -n 1)
[ -f serial.txt ] || fail "serial.txt does not exist yet."
[ "$(tr -d '[:space:]' < serial.txt)" = "$want" ] || fail "serial.txt should hold the serial number from the sample state file, and nothing else."
