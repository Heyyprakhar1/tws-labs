. "$LAB_LIB"

[ -f pkg-incident/reports/broken-package.txt ] || fail "pkg-incident/reports/broken-package.txt does not exist."
pkg=$(cat pkg-incident/reports/broken-package.txt 2>/dev/null | tr -d '[:space:]')
[ -n "$pkg" ] || fail "reports/broken-package.txt is empty."

orig_status=$(awk -v p="$pkg" 'BEGIN { RS=""; FS="\n" } $0 ~ ("Package: " p "($|\n)") { for (i=1; i<=NF; i++) if ($i ~ /^Status:/) print $i }' pkg-incident/var/lib/dpkg/status.orig 2>/dev/null || true)
[ "$orig_status" = "Status: install ok half-configured" ] || fail "Package '$pkg' was not in half-configured status in the database."
