. "$LAB_LIB"
[ -f errors.txt ] || fail "errors.txt does not exist yet."
[ "$(wc -l < errors.txt)" -eq 2 ] || fail "errors.txt should contain exactly the 2 ERROR lines."
! grep -qv ERROR errors.txt || fail "errors.txt should only contain lines with ERROR."
