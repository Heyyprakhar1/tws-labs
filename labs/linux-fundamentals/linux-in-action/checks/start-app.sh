. "$LAB_LIB"
[ -x start.sh ] || fail "start.sh is not executable yet."
[ -f .service_status ] && [ "$(cat .service_status)" = "ONLINE" ] || fail "Run ./start.sh to launch the service."
