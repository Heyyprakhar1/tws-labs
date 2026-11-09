. "$LAB_LIB"

[ -f port-incident/.socket-audit.passed ] || fail "Run ./port-incident/bin/verify-sockets to complete recovery verification."
