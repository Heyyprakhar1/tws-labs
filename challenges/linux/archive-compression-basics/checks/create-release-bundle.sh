. "$LAB_LIB"

BUNDLE="backup-incident/release/app-bundle.tar.gz"
[ -f "$BUNDLE" ] || fail "backup-incident/release/app-bundle.tar.gz does not exist."
gzip -t "$BUNDLE" 2>/dev/null || fail "app-bundle.tar.gz is not a valid gzip tarball."

SERVER_MEMBER=$(tar -tzf "$BUNDLE" 2>/dev/null | grep 'server\.js$' | head -n1 || true)
PKG_MEMBER=$(tar -tzf "$BUNDLE" 2>/dev/null | grep 'package\.json$' | head -n1 || true)

[ -n "$SERVER_MEMBER" ] || fail "app-bundle.tar.gz is missing application source files (server.js)."
[ -n "$PKG_MEMBER" ] || fail "app-bundle.tar.gz is missing package.json."

tar -xOf "$BUNDLE" "$SERVER_MEMBER" | grep -q "App running" || fail "server.js inside app-bundle.tar.gz has invalid content."
tar -xOf "$BUNDLE" "$PKG_MEMBER" | grep -q '"name": "service"' || fail "package.json inside app-bundle.tar.gz has invalid content."

! tar -tzf "$BUNDLE" 2>/dev/null | grep -Eq '(\.tmp|cache/)' || fail "app-bundle.tar.gz contains excluded .tmp files or cache directory."
