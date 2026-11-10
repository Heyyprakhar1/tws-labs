. "$LAB_LIB"

CONF="port-incident/config/proxy.env"
[ -f "$CONF" ] || fail "Configuration file port-incident/config/proxy.env missing."

PROXY_BIND=$(grep -E '^[[:space:]]*PROXY_BIND=' "$CONF" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
METRICS_BIND=$(grep -E '^[[:space:]]*METRICS_BIND=' "$CONF" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ "$PROXY_BIND" = "0.0.0.0" ] || fail "PROXY_BIND must be set to 0.0.0.0."
[ "$METRICS_BIND" = "0.0.0.0" ] || fail "METRICS_BIND must be set to 0.0.0.0 (currently '$METRICS_BIND')."
