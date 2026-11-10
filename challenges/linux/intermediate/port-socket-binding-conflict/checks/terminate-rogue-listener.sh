. "$LAB_LIB"

PORTS_FILE="port-incident/config/ports.env"
if [ -f "$PORTS_FILE" ]; then
  . "$PORTS_FILE"
fi
PORT_HTTP="${PORT_HTTP:-18080}"

# 1. Verify recorded rogue-listener is dead
PID_FILE="port-incident/var/run/rogue-listener.pid"
if [ -f "$PID_FILE" ]; then
  ROGUE_PID=$(cat "$PID_FILE" | tr -d '[:space:]')
  if [ -n "$ROGUE_PID" ] && [ -d "/proc/$ROGUE_PID" ]; then
    CMDLINE=$(cat "/proc/$ROGUE_PID/cmdline" 2>/dev/null | tr '\0' ' ' || true)
    if echo "$CMDLINE" | grep -q "rogue-listener"; then
      fail "rogue-listener (PID $ROGUE_PID) is still running. Terminate it to release the port."
    fi
  fi
fi

# 2. Check for any rogue-listener process belonging to this workspace
for pid in $(pgrep -u "$UID" -f "rogue-listener" 2>/dev/null || true); do
  if [ "$pid" != "$$" ] && [ "$pid" != "${BASHPID:-$$}" ]; then
    CMDLINE=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || true)
    if echo "$CMDLINE" | grep -q "$HOME/port-incident/bin/rogue-listener"; then
      fail "rogue-listener process (PID $pid) is still active."
    fi
  fi
done

# 3. Verify PORT_HTTP is not held by rogue-listener
if command -v ss >/dev/null 2>&1; then
  SS_OUT=$(ss -tlpn 2>/dev/null || true)
  if echo "$SS_OUT" | grep -q ":$PORT_HTTP " && echo "$SS_OUT" | grep -q "rogue-listener"; then
    fail "Port $PORT_HTTP is still held by rogue-listener."
  fi
fi
