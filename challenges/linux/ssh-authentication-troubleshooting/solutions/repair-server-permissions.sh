#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

chmod 0750 "$INCIDENT/server/home/app-operator"
chmod 0700 "$INCIDENT/server/home/app-operator/.ssh"
chmod 0600 "$INCIDENT/server/home/app-operator/.ssh/authorized_keys"
