#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

if [ ! -d "$INCIDENT" ]; then
  "$(dirname "$0")/../setup.sh"
fi

"$(dirname "$0")/../solutions/repair-client-key.sh"
