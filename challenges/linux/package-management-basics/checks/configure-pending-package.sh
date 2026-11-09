. "$LAB_LIB"

[ -f pkg-incident/etc/app-web/runtime.conf ] || fail "pkg-incident/etc/app-web/runtime.conf was not created by post-install configuration."
grep -q "APP_INITIALIZED=true" pkg-incident/etc/app-web/runtime.conf 2>/dev/null || fail "runtime.conf does not indicate APP_INITIALIZED=true."
! grep -q "half-configured" pkg-incident/var/lib/dpkg/status 2>/dev/null || fail "var/lib/dpkg/status still contains half-configured packages."
