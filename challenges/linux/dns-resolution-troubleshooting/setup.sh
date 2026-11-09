#!/bin/bash
set -euo pipefail

# ─── 1. Base Resolution Decision Sequence ───
BASE="${LAB_HOME:-$HOME}"
[ -n "$BASE" ] && [ -d "$BASE" ] || { echo "Fatal: HOME not set." >&2; exit 1; }

INCIDENT="$BASE/dns-incident"
rm -rf "$INCIDENT"
mkdir -p "$INCIDENT"/{bin,etc,dns,reports,var/log,var/run}

# ─── 2. Mock DNS Records (source of truth for the simulated DNS server) ───
cat << 'DNS_EOF' > "$INCIDENT/dns/records"
# Simulated internal DNS zone records
# Format: FQDN IP
db.internal.corp 10.0.2.15
api.internal.corp 10.0.2.20
cache.internal.corp 10.0.2.30
dns.internal.corp 10.0.0.53
DNS_EOF
chmod 0644 "$INCIDENT/dns/records"

# ─── 3. Poisoned hosts file (the incident) ───
cat << 'HOSTS_EOF' > "$INCIDENT/etc/hosts"
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
# Legacy migration entry — do not remove without approval
192.0.2.1 db.internal.corp db
HOSTS_EOF
chmod 0644 "$INCIDENT/etc/hosts"

# ─── 4. DNS resolver configuration (defective search domain) ───
cat << 'RESOLV_EOF' > "$INCIDENT/etc/resolv.conf"
# DNS resolver configuration
nameserver 10.0.0.53
search dev.corp
RESOLV_EOF
chmod 0644 "$INCIDENT/etc/resolv.conf"

# ─── 5. NSS configuration (files before dns: poisoned hosts takes precedence) ───
cat << 'NSS_EOF' > "$INCIDENT/etc/nsswitch.conf"
# Name Service Switch configuration
passwd:     files
group:      files
shadow:     files
hosts:      files dns
networks:   files
protocols:  files
services:   files
NSS_EOF
chmod 0644 "$INCIDENT/etc/nsswitch.conf"

# ─── 6. Incident status telemetry ───
cat << 'STATUS_EOF' > "$INCIDENT/reports/incident.status"
[INCIDENT TELEMETRY] 2026-11-07T09:45:00Z
SEVERITY: SEV-2 DEGRADED SERVICE
DESCRIPTION: Application connects to wrong database endpoint. db.internal.corp resolves to unexpected IP.
SYMPTOMS OBSERVED:
  - Database connection timeouts to db.internal.corp
  - Application logs show connection to 192.0.2.1 instead of expected 10.0.2.15
  - Direct DNS queries appear to return correct results
SIMULATION BOUNDARY:
  Controlled userland DNS/NSS simulation inside ~/dns-incident.
  No host /etc files, host network settings, or real DNS servers are modified.
AVAILABLE COMMANDS:
  ./bin/resolve-host <hostname>     - Resolve hostname using configured NSS order
  ./bin/dig-dns <hostname>          - Query DNS records directly (bypasses hosts file)
  ./bin/validate-resolution         - Verify end-to-end resolution
ACTION REQUIRED:
  1. Diagnose why db.internal.corp resolves incorrectly (reports/resolution-triage.env)
  2. Remove the poisoned hosts entry
  3. Verify and correct resolver and NSS configuration (search internal.corp, hosts: files dns)
  4. Validate end-to-end resolution with ./bin/validate-resolution
STATUS_EOF
chmod 0644 "$INCIDENT/reports/incident.status"

# ─── 7. bin/resolve-host — NSS-aware resolver ───
cat << 'RESOLVE_EOF' > "$INCIDENT/bin/resolve-host"
#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"

MODE="full"
HOSTNAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --source|-s)
      MODE="source"
      ;;
    --ip|-i)
      MODE="ip"
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      HOSTNAME="$1"
      ;;
  esac
  shift
done

[ -n "$HOSTNAME" ] || { echo "Usage: resolve-host [--source|--ip] <hostname>" >&2; exit 1; }

HOSTS_FILE="$ROOT/etc/hosts"
RESOLV_FILE="$ROOT/etc/resolv.conf"
NSS_FILE="$ROOT/etc/nsswitch.conf"
DNS_RECORDS="$ROOT/dns/records"

# 1. Parse NSS hosts order
nss_order="files dns"
if [ -f "$NSS_FILE" ]; then
  nss_line=$(grep -E '^\s*hosts:\s' "$NSS_FILE" 2>/dev/null | head -n1 || true)
  if [ -n "$nss_line" ]; then
    nss_order=$(echo "$nss_line" | sed 's/^[[:space:]]*hosts:[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
fi

# 2. Parse search domain and nameserver from resolv.conf
search_domain=""
nameserver=""
if [ -f "$RESOLV_FILE" ]; then
  search_domain=$(grep -E '^\s*search\s' "$RESOLV_FILE" 2>/dev/null | head -n1 | awk '{print $2}' || true)
  nameserver=$(grep -E '^\s*nameserver\s' "$RESOLV_FILE" 2>/dev/null | head -n1 | awk '{print $2}' || true)
fi

# Helper: resolve via files (hosts file)
resolve_files() {
  local target="$1"
  [ -f "$HOSTS_FILE" ] || return 1

  # Search hosts file for exact hostname or alias
  local match
  match=$(awk -v h="$target" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      ip = $1
      for (i = 2; i <= NF; i++) {
        if ($i == h) {
          print ip
          exit
        }
      }
    }
  ' "$HOSTS_FILE")

  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  return 1
}

# Helper: resolve via dns (simulated DNS zone records)
resolve_dns() {
  local target="$1"
  [ -f "$DNS_RECORDS" ] || return 1

  # Nameserver must be configured to 10.0.0.53
  if [ "$nameserver" != "10.0.0.53" ]; then
    return 1
  fi

  # A. Try exact match
  local match
  match=$(awk -v h="$target" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == h { print $2; exit }
  ' "$DNS_RECORDS")

  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi

  # B. If target does not contain a dot, try search domain
  if ! echo "$target" | grep -q '\.' && [ -n "$search_domain" ]; then
    local fqdn="${target}.${search_domain}"
    match=$(awk -v h="$fqdn" '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*$/ { next }
      $1 == h { print $2; exit }
    ' "$DNS_RECORDS")
    if [ -n "$match" ]; then
      echo "$match"
      return 0
    fi
  fi

  return 1
}

resolved_ip=""
source_used=""

# Walk NSS sources in configured order
for source in $nss_order; do
  case "$source" in
    files)
      if ip=$(resolve_files "$HOSTNAME"); then
        resolved_ip="$ip"
        source_used="files"
        break
      fi
      ;;
    dns)
      if ip=$(resolve_dns "$HOSTNAME"); then
        resolved_ip="$ip"
        source_used="dns"
        break
      fi
      ;;
    *)
      # Unknown source, skip
      ;;
  esac
done

if [ -n "$resolved_ip" ]; then
  case "$MODE" in
    source)
      echo "$source_used"
      ;;
    ip)
      echo "$resolved_ip"
      ;;
    full)
      printf "%-16s %s (source: %s)\n" "$resolved_ip" "$HOSTNAME" "$source_used"
      ;;
  esac
  exit 0
else
  echo "resolve-host: $HOSTNAME: Host name lookup failure" >&2
  exit 2
fi
RESOLVE_EOF
chmod 0755 "$INCIDENT/bin/resolve-host"

# ─── 8. bin/dig-dns — Direct DNS query tool (bypasses hosts/NSS) ───
cat << 'DIG_EOF' > "$INCIDENT/bin/dig-dns"
#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"

DNS_RECORDS="$ROOT/dns/records"
RESOLV_FILE="$ROOT/etc/resolv.conf"

SHORT_OUTPUT=false
HOSTNAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    +short|--short|-s)
      SHORT_OUTPUT=true
      ;;
    -*)
      # Ignore other flags
      ;;
    *)
      HOSTNAME="$1"
      ;;
  esac
  shift
done

[ -n "$HOSTNAME" ] || { echo "Usage: dig-dns [+short] <hostname>" >&2; exit 1; }

nameserver=""
search_domain=""
if [ -f "$RESOLV_FILE" ]; then
  nameserver=$(grep -E '^\s*nameserver\s' "$RESOLV_FILE" 2>/dev/null | head -n1 | awk '{print $2}' || true)
  search_domain=$(grep -E '^\s*search\s' "$RESOLV_FILE" 2>/dev/null | head -n1 | awk '{print $2}' || true)
fi

if [ -z "$nameserver" ] || [ "$nameserver" != "10.0.0.53" ]; then
  echo ";; connection timed out; no servers could be reached" >&2
  exit 1
fi

if [ ! -f "$DNS_RECORDS" ]; then
  echo ";; connection timed out; no servers could be reached" >&2
  exit 1
fi

result=""
query_name="$HOSTNAME"

# 1. Exact match in DNS records
result=$(awk -v h="$query_name" '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  $1 == h { print $2; exit }
' "$DNS_RECORDS")

# 2. Try with search domain if short name
if [ -z "$result" ] && ! echo "$query_name" | grep -q '\.' && [ -n "$search_domain" ]; then
  fqdn="${query_name}.${search_domain}"
  result=$(awk -v h="$fqdn" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == h { print $2; exit }
  ' "$DNS_RECORDS")
  if [ -n "$result" ]; then
    query_name="$fqdn"
  fi
fi

if [ "$SHORT_OUTPUT" = true ]; then
  if [ -n "$result" ]; then
    echo "$result"
    exit 0
  else
    exit 1
  fi
fi

echo ""
echo "; <<>> dig-dns 1.0 <<>> $HOSTNAME"
echo ";; QUESTION SECTION:"
echo ";${query_name}.          IN      A"
echo ""

if [ -n "$result" ]; then
  echo ";; ANSWER SECTION:"
  printf "%-24s 300     IN      A       %s\n" "${query_name}." "$result"
  echo ""
  echo ";; SERVER: ${nameserver}#53(${nameserver})"
  echo ";; MSG SIZE  rcvd: 56"
  exit 0
else
  echo ";; ANSWER SECTION:"
  echo ";; (no records found)"
  echo ""
  echo ";; SERVER: ${nameserver}#53(${nameserver})"
  echo ";; MSG SIZE  rcvd: 40"
  exit 1
fi
DIG_EOF
chmod 0755 "$INCIDENT/bin/dig-dns"

# ─── 9. bin/validate-resolution — End-to-end verifier ───
cat << 'VALIDATE_EOF' > "$INCIDENT/bin/validate-resolution"
#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"
RESOLVE="$DIR/resolve-host"
DIG="$DIR/dig-dns"
MARKER="$ROOT/.resolution-validated"

fail() {
  echo "[VALIDATION FAILED] $*" >&2
  exit 1
}

echo "=== DNS & Name Resolution End-to-End Validator ==="
echo ""

# 1. db.internal.corp must resolve to 10.0.2.15 via NSS
db_nss=$("$RESOLVE" --ip db.internal.corp 2>/dev/null) || fail "resolve-host failed for db.internal.corp."
[ "$db_nss" = "10.0.2.15" ] || fail "db.internal.corp resolved to '$db_nss' via NSS, expected '10.0.2.15'."
echo "[OK] db.internal.corp -> $db_nss (NSS)"

# 2. api.internal.corp must resolve to 10.0.2.20 via NSS
api_nss=$("$RESOLVE" --ip api.internal.corp 2>/dev/null) || fail "resolve-host failed for api.internal.corp."
[ "$api_nss" = "10.0.2.20" ] || fail "api.internal.corp resolved to '$api_nss' via NSS, expected '10.0.2.20'."
echo "[OK] api.internal.corp -> $api_nss (NSS)"

# 3. Short hostname 'db' must resolve via search domain
db_short=$("$RESOLVE" --ip db 2>/dev/null) || fail "resolve-host failed for short hostname 'db'."
[ "$db_short" = "10.0.2.15" ] || fail "Short hostname 'db' resolved to '$db_short', expected '10.0.2.15' via search domain."
echo "[OK] db (short) -> $db_short (search domain)"

# 4. localhost must resolve correctly to 127.0.0.1
lo=$("$RESOLVE" --ip localhost 2>/dev/null) || fail "resolve-host failed for localhost."
[ "$lo" = "127.0.0.1" ] || fail "localhost resolved to '$lo', expected '127.0.0.1'."
echo "[OK] localhost -> $lo"

# 5. Direct DNS must match NSS for db.internal.corp
db_dns=$("$DIG" +short db.internal.corp 2>/dev/null) || fail "dig-dns failed for db.internal.corp."
[ "$db_dns" = "10.0.2.15" ] || fail "Direct DNS for db.internal.corp returned '$db_dns', expected '10.0.2.15'."
echo "[OK] db.internal.corp -> $db_dns (direct DNS)"

# 6. Direct DNS must match NSS for api.internal.corp
api_dns=$("$DIG" +short api.internal.corp 2>/dev/null) || fail "dig-dns failed for api.internal.corp."
[ "$api_dns" = "10.0.2.20" ] || fail "Direct DNS for api.internal.corp returned '$api_dns', expected '10.0.2.20'."
echo "[OK] api.internal.corp -> $api_dns (direct DNS)"

# 7. Poisoned address 192.0.2.1 must not appear in etc/hosts
if grep -qE '^\s*192\.0\.2\.1\s' "$ROOT/etc/hosts" 2>/dev/null; then
  fail "Poisoned entry 192.0.2.1 still present in etc/hosts."
fi
echo "[OK] No poisoned 192.0.2.1 entry in hosts file"

# 8. NSS order must be 'files dns'
nss_line=$(grep -E '^\s*hosts:\s' "$ROOT/etc/nsswitch.conf" 2>/dev/null | head -n1 || true)
nss_order=$(echo "$nss_line" | sed 's/^[[:space:]]*hosts:[[:space:]]*//' | sed 's/[[:space:]]*$//')
[ "$nss_order" = "files dns" ] || fail "NSS hosts order is '$nss_order', expected 'files dns'."
echo "[OK] NSS hosts order: files dns"

# 9. Resolver must have nameserver 10.0.0.53 and search internal.corp
grep -Eq '^\s*nameserver\s+10\.0\.0\.53(\s|$)' "$ROOT/etc/resolv.conf" || fail "nameserver 10.0.0.53 missing in resolv.conf."
grep -Eq '^\s*search\s+internal\.corp(\s|$)' "$ROOT/etc/resolv.conf" || fail "search internal.corp missing in resolv.conf."
echo "[OK] resolv.conf: nameserver 10.0.0.53, search internal.corp"

echo ""
echo "=== All resolution checks passed ==="

# Write success marker
cat << MARKER_EOF > "$MARKER"
RESOLUTION_STATUS=VALIDATED
DB_RESOLVED=10.0.2.15
API_RESOLVED=10.0.2.20
NSS_ORDER=files_dns
NAMESERVER=10.0.0.53
SEARCH_DOMAIN=internal.corp
VALIDATED_BY=resolution_validator_v1
MARKER_EOF
chmod 0644 "$MARKER"

echo "[OK] Generated .resolution-validated marker."
exit 0
VALIDATE_EOF
chmod 0755 "$INCIDENT/bin/validate-resolution"

echo "DNS incident environment provisioned successfully."
