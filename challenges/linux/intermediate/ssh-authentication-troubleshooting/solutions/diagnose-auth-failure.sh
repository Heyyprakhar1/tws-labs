#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

mkdir -p "$INCIDENT/reports"

cat << 'EOF' > "$INCIDENT/reports/auth-triage.env"
CLIENT_KEY_PATH=client/.ssh/id_rsa
CLIENT_KEY_PERMS=0644
SERVER_STRICTMODES_ERROR=bad ownership or modes for directory /home/app-operator
PUBKEY_MATCH=false
ROOT_CAUSE=unsafe permissions on client private key and server home directory, and mismatched public key in authorized_keys
EOF
