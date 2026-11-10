#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

CLIENT_KEY="$INCIDENT/client/.ssh/id_rsa"
AUTH_KEYS="$INCIDENT/server/home/app-operator/.ssh/authorized_keys"

[ -f "$CLIENT_KEY" ] || fail "Client private key $CLIENT_KEY does not exist."
[ -f "$AUTH_KEYS" ] || fail "Authorized keys file $AUTH_KEYS does not exist."

# 1. Check client private key permissions
KEY_MODE=$(stat -c '%a' "$CLIENT_KEY")
KEY_OCT=$((8#$KEY_MODE))

# Private keys must NOT be accessible by group or others: (mode & 0077) == 0
if [ $((KEY_OCT & 8#077)) -ne 0 ]; then
  fail "Client private key has mode $KEY_MODE: it must be 0600 or 0400 (not accessible by group or others)."
fi

# 2. Cryptographic key match between client key and authorized_keys via OpenSSL
KEY_MATCH=$(node -e '
const fs = require("fs");
const path = require("path");

const clientKeyPath = process.argv[1];
const authKeysPath = process.argv[2];
const incidentDir = process.argv[3];
const libPath = path.join(incidentDir, "lib", "ssh-crypto.js");
const { verifyKeyAgreement, parseAuthorizedKeys } = require(libPath);

try {
  const authKeysContent = fs.readFileSync(authKeysPath, "utf8");
  const keys = parseAuthorizedKeys(authKeysContent);
  if (keys.length === 0) {
    console.log("NO_VALID_PUBKEYS");
    process.exit(0);
  }
  const res = verifyKeyAgreement(clientKeyPath, authKeysContent);
  console.log(res.verified ? "MATCH" : "MISMATCH");
} catch (e) {
  console.log("ERROR:" + e.message);
}
' "$CLIENT_KEY" "$AUTH_KEYS" "$INCIDENT" 2>/dev/null || echo "ERROR")

case "$KEY_MATCH" in
  MATCH)
    ;;
  MISMATCH)
    fail "authorized_keys does not contain the public key corresponding to client/.ssh/id_rsa (OpenSSL verification failed)."
    ;;
  NO_VALID_PUBKEYS)
    fail "authorized_keys does not contain any valid public keys."
    ;;
  *)
    fail "Cryptographic key verification failed ($KEY_MATCH)."
    ;;
esac
