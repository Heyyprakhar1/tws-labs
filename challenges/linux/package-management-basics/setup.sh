#!/bin/bash
set -euo pipefail

BASE="$HOME/pkg-incident"
rm -rf "$BASE"
mkdir -p "$BASE/var/lib/dpkg/info" "$BASE/bin" "$BASE/pool" "$BASE/reports" "$BASE/etc/app-web"

# 1. Provision offline package bundle in pool
cat << 'META_EOF' > "$BASE/pool/libmsg-proto.meta"
Package: libmsg-proto
Status: install ok installed
Priority: optional
Section: libs
Version: 1.0.4
Depends: core-utils
Maintainer: Lab Ops Team
META_EOF

# 2. Provision actual post-installation trigger script for app-web
cat << 'POSTINST_EOF' > "$BASE/var/lib/dpkg/info/app-web.postinst"
#!/bin/bash
set -euo pipefail
# Ascend 4 levels from var/lib/dpkg/info to the challenge root (pkg-incident)
BASE_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
mkdir -p "$BASE_DIR/etc/app-web"
cat << 'CONF_EOF' > "$BASE_DIR/etc/app-web/runtime.conf"
APP_INITIALIZED=true
APP_PORT=8080
CONF_EOF
exit 0
POSTINST_EOF
chmod 0755 "$BASE/var/lib/dpkg/info/app-web.postinst"

# 3. Provision status database with broken app-web and unsatisfied app-cache
cat << 'STATUS_EOF' > "$BASE/var/lib/dpkg/status"
Package: core-utils
Status: install ok installed
Priority: required
Section: utils
Version: 9.1-1
Maintainer: Lab Ops Team

Package: app-web
Status: install ok half-configured
Priority: optional
Section: web
Version: 2.4.1
Depends: core-utils
Maintainer: Lab Ops Team

Package: app-cache
Status: install ok installed
Priority: optional
Section: database
Version: 1.2.0
Depends: core-utils, libmsg-proto
Maintainer: Lab Ops Team
STATUS_EOF
chmod 0644 "$BASE/var/lib/dpkg/status"

# 4. Save a copy of the pristine initial status database for dynamic verification
cp "$BASE/var/lib/dpkg/status" "$BASE/var/lib/dpkg/status.orig"
chmod 0644 "$BASE/var/lib/dpkg/status.orig"

# 5. Provision deterministic user-space package manager tool
cat << 'TOOL_EOF' > "$BASE/bin/pkg-tool"
#!/bin/bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATUS_FILE="$BASE_DIR/var/lib/dpkg/status"

CMD="${1:-}"
case "$CMD" in
  status)
    cat "$STATUS_FILE"
    ;;
  install)
    PKG_META="${2:-}"
    # Resolve relative to cwd or relative to BASE_DIR
    if [ ! -f "$PKG_META" ] && [ -f "$BASE_DIR/$PKG_META" ]; then
      PKG_META="$BASE_DIR/$PKG_META"
    fi
    [ -f "$PKG_META" ] || { echo "Error: Package meta file not found: ${2:-}" >&2; exit 1; }
    PKG_NAME=$(grep '^Package:' "$PKG_META" | cut -d' ' -f2)
    if grep -q "^Package: $PKG_NAME$" "$STATUS_FILE"; then
      echo "Package $PKG_NAME is already installed."
    else
      printf "\n" >> "$STATUS_FILE"
      cat "$PKG_META" >> "$STATUS_FILE"
      echo "Successfully installed $PKG_NAME."
    fi
    ;;
  configure)
    PKG_NAME="${2:-}"
    [ -n "$PKG_NAME" ] || { echo "Usage: pkg-tool configure <package>" >&2; exit 1; }
    if ! grep -q "^Package: $PKG_NAME$" "$STATUS_FILE"; then
      echo "Error: Package $PKG_NAME not found." >&2
      exit 1
    fi
    # Execute actual post-install script if present
    POSTINST="$BASE_DIR/var/lib/dpkg/info/$PKG_NAME.postinst"
    if [ -x "$POSTINST" ]; then
      echo "Running post-install configuration for $PKG_NAME ..."
      "$POSTINST" configure || { echo "Error: Post-install script failed." >&2; exit 1; }
    fi
    awk -v pkg="$PKG_NAME" '
      BEGIN { RS=""; FS="\n"; ORS="\n\n" }
      $0 ~ "Package: " pkg {
        sub("Status: install ok half-configured", "Status: install ok installed")
      }
      { print }
    ' "$STATUS_FILE" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' > "${STATUS_FILE}.tmp"
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    echo "Configuration for $PKG_NAME completed successfully."
    ;;
  *)
    echo "Usage: pkg-tool {status|install <pkg.meta>|configure <pkg>}" >&2
    exit 1
    ;;
esac
TOOL_EOF
chmod 0755 "$BASE/bin/pkg-tool"

# 6. Remove any prior marker
rm -f "$BASE/.pkg-audit.passed"

# 7. Provision verification runner checking concrete runtime and status outcomes
cat << 'VERIFY_EOF' > "$BASE/verify-packages"
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

STATUS_FILE="var/lib/dpkg/status"
ORIG_FILE="var/lib/dpkg/status.orig"
[ -f "$STATUS_FILE" ] || { echo "FAIL: var/lib/dpkg/status missing." >&2; exit 1; }
[ -f "$ORIG_FILE" ] || { echo "FAIL: var/lib/dpkg/status.orig missing." >&2; exit 1; }

# 1. Validate Task 1 report identifies genuine broken package
[ -f "reports/broken-package.txt" ] || { echo "FAIL: reports/broken-package.txt missing." >&2; exit 1; }
REPORTED_PKG=$(cat reports/broken-package.txt | tr -d '[:space:]')
[ -n "$REPORTED_PKG" ] || { echo "FAIL: reports/broken-package.txt is empty." >&2; exit 1; }

ORIG_STATUS=$(awk -v p="$REPORTED_PKG" 'BEGIN { RS=""; FS="\n" } $0 ~ ("Package: " p "($|\n)") { for (i=1; i<=NF; i++) if ($i ~ /^Status:/) print $i }' "$ORIG_FILE")
if [ "$ORIG_STATUS" != "Status: install ok half-configured" ]; then
  echo "FAIL: Package '$REPORTED_PKG' was not in half-configured status in the database." >&2
  exit 1
fi

# 2. Check Task 2 dependency installation
if ! grep -q "^Package: libmsg-proto$" "$STATUS_FILE"; then
  echo "FAIL: Package libmsg-proto is missing from status database." >&2
  exit 1
fi

# 3. Check Task 3 post-install concrete outcome
[ -f "etc/app-web/runtime.conf" ] || { echo "FAIL: etc/app-web/runtime.conf was not generated by post-install trigger." >&2; exit 1; }
grep -q "APP_INITIALIZED=true" "etc/app-web/runtime.conf" || { echo "FAIL: runtime.conf does not indicate APP_INITIALIZED=true." >&2; exit 1; }

# 4. Check zero half-configured packages
if grep -q "half-configured" "$STATUS_FILE"; then
  echo "FAIL: Database still contains half-configured packages." >&2
  exit 1
fi

# 5. Full dependency consistency verification:
INSTALLED_PKGS=$(awk -v RS='' '/Status: install ok installed/ { for (i=1; i<=NF; i++) if ($i == "Package:") print $(i+1) }' "$STATUS_FILE")

while IFS= read -r dep_line; do
  [ -z "$dep_line" ] && continue
  IFS=',' read -ra DEPS <<< "$dep_line"
  for dep in "${DEPS[@]}"; do
    clean_dep=$(echo "$dep" | tr -d '[:space:]')
    [ -z "$clean_dep" ] && continue
    if ! echo "$INSTALLED_PKGS" | grep -qx "$clean_dep"; then
      echo "FAIL: Unsatisfied dependency: $clean_dep is not installed." >&2
      exit 1
    fi
  done
done < <(grep '^Depends:' "$STATUS_FILE" | cut -d: -f2-)

cat << 'MARKER' > .pkg-audit.passed
{"status": "PASSED", "audit": "package-management-basics"}
MARKER
echo "SUCCESS: Package states, post-installation outcomes, and dependency consistency verified."
exit 0
VERIFY_EOF
chmod 0755 "$BASE/verify-packages"
