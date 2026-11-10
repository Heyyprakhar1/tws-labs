. "$LAB_LIB"

grep -q "^Package: libmsg-proto$" pkg-incident/var/lib/dpkg/status 2>/dev/null || fail "libmsg-proto is not installed in var/lib/dpkg/status."
awk -v RS='' '/Package: libmsg-proto/' pkg-incident/var/lib/dpkg/status 2>/dev/null | grep -q "Status: install ok installed" || fail "libmsg-proto must have Status: install ok installed."
