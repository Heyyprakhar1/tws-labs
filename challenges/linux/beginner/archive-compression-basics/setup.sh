#!/bin/bash
set -euo pipefail

BASE="$HOME/backup-incident"
rm -rf "$BASE"
mkdir -p "$BASE/incoming" "$BASE/logs" "$BASE/app/src" "$BASE/app/cache" "$BASE/release"

# 1. Provision payload tarball with obfuscated .bin extension
TMP_STAGING=$(mktemp -d)
mkdir -p "$TMP_STAGING/config" "$TMP_STAGING/data"
echo "DB_RESTORE_HOST=10.0.0.5" > "$TMP_STAGING/config/database.env"
echo "RESTORE_BLOCK_DATA" > "$TMP_STAGING/data/records.db"
tar -czf "$BASE/incoming/backup-payload.bin" -C "$TMP_STAGING" config data
rm -rf "$TMP_STAGING"

# 2. Provision uncompressed legacy log
for i in {1..50}; do
  echo "2026-11-01 [AUDIT] Event record ID $i OK"
done > "$BASE/logs/legacy-audit.log"

# 3. Provision application directory with transient files
echo "console.log('App running');" > "$BASE/app/src/server.js"
echo '{"name": "service", "version": "1.0.0"}' > "$BASE/app/package.json"
echo "CACHE_BLOB" > "$BASE/app/cache/session.cache"
echo "TMP_SWAP" > "$BASE/app/src/build.tmp"

# 4. Remove any prior marker
rm -f "$BASE/.archive-audit.passed"

# 5. Provision verification runner checking concrete file outcomes
cat << 'VERIFY_EOF' > "$BASE/verify-archive"
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 1. Verify Task 1 extraction
[ -d "restore" ] || { echo "FAIL: restore/ directory missing." >&2; exit 1; }
[ -f "restore/config/database.env" ] || { echo "FAIL: restore/config/database.env missing." >&2; exit 1; }
[ -f "restore/data/records.db" ] || { echo "FAIL: restore/data/records.db missing." >&2; exit 1; }
grep -q "DB_RESTORE_HOST=10.0.0.5" "restore/config/database.env" || { echo "FAIL: Extracted database.env content corrupted." >&2; exit 1; }

# 2. Verify Task 2 in-place compression
[ -f "logs/legacy-audit.log.gz" ] || { echo "FAIL: logs/legacy-audit.log.gz missing." >&2; exit 1; }
[ ! -f "logs/legacy-audit.log" ] || { echo "FAIL: Uncompressed logs/legacy-audit.log still exists. Compression must be in-place." >&2; exit 1; }
gzip -t "logs/legacy-audit.log.gz" 2>/dev/null || { echo "FAIL: logs/legacy-audit.log.gz is corrupt." >&2; exit 1; }
zcat "logs/legacy-audit.log.gz" 2>/dev/null | grep -q "Event record ID 50 OK" || { echo "FAIL: Decompressed log content mismatch." >&2; exit 1; }

# 3. Verify Task 3 release bundle
BUNDLE="release/app-bundle.tar.gz"
[ -f "$BUNDLE" ] || { echo "FAIL: $BUNDLE missing." >&2; exit 1; }
gzip -t "$BUNDLE" 2>/dev/null || { echo "FAIL: $BUNDLE is not valid gzip." >&2; exit 1; }

SERVER_MEMBER=$(tar -tzf "$BUNDLE" 2>/dev/null | grep 'server\.js$' | head -n1 || true)
PKG_MEMBER=$(tar -tzf "$BUNDLE" 2>/dev/null | grep 'package\.json$' | head -n1 || true)

[ -n "$SERVER_MEMBER" ] || { echo "FAIL: server.js missing from $BUNDLE." >&2; exit 1; }
[ -n "$PKG_MEMBER" ] || { echo "FAIL: package.json missing from $BUNDLE." >&2; exit 1; }

tar -xOf "$BUNDLE" "$SERVER_MEMBER" | grep -q "App running" || {
  echo "FAIL: server.js inside $BUNDLE has corrupted content." >&2
  exit 1
}
tar -xOf "$BUNDLE" "$PKG_MEMBER" | grep -q '"name": "service"' || {
  echo "FAIL: package.json inside $BUNDLE has corrupted content." >&2
  exit 1
}

if tar -tzf "$BUNDLE" 2>/dev/null | grep -Eq '(\.tmp|cache/)'; then
  echo "FAIL: $BUNDLE contains excluded .tmp files or cache directory." >&2
  exit 1
fi

cat << 'MARKER' > .archive-audit.passed
{"status": "PASSED", "audit": "archive-compression-basics"}
MARKER
echo "SUCCESS: Archive extraction, in-place compression, and bundle packaging verified."
exit 0
VERIFY_EOF
chmod 0755 "$BASE/verify-archive"
