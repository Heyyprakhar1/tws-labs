#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

chmod 0600 "$INCIDENT/client/.ssh/id_rsa"
"$INCIDENT/bin/ssh-keygen" -y -f "$INCIDENT/client/.ssh/id_rsa" > "$INCIDENT/server/home/app-operator/.ssh/authorized_keys"
chmod 0600 "$INCIDENT/server/home/app-operator/.ssh/authorized_keys"
