#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME:-/root}/deadlock-incident"
CONF_FILE="$BASE_DIR/config/service.env"

sed -i 's/^ORDER_LOCKS_BY_ID=.*/ORDER_LOCKS_BY_ID=true/' "$CONF_FILE"
if ! grep -q "^ORDER_LOCKS_BY_ID=" "$CONF_FILE"; then
  echo "ORDER_LOCKS_BY_ID=true" >> "$CONF_FILE"
fi

"$BASE_DIR/bin/order-ctl" restart
