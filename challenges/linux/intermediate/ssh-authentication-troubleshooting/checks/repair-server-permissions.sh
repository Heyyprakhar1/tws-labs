#!/bin/bash
set -u
. "${LAB_LIB:-$(dirname "$0")/../../../../labs/lib.sh}"

BASE="${LAB_HOME:-$HOME}"
INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"

SERVER_HOME="$INCIDENT/server/home/app-operator"
SERVER_SSH="$SERVER_HOME/.ssh"
AUTH_KEYS="$SERVER_SSH/authorized_keys"

[ -d "$SERVER_HOME" ] || fail "Server home directory $SERVER_HOME does not exist."
[ -d "$SERVER_SSH" ] || fail "Server .ssh directory $SERVER_SSH does not exist."
[ -f "$AUTH_KEYS" ] || fail "Authorized keys file $AUTH_KEYS does not exist."

HOME_MODE=$(stat -c '%a' "$SERVER_HOME")
SSH_MODE=$(stat -c '%a' "$SERVER_SSH")
KEYS_MODE=$(stat -c '%a' "$AUTH_KEYS")

HOME_UID=$(stat -c '%u' "$SERVER_HOME")
SSH_UID=$(stat -c '%u' "$SERVER_SSH")
KEYS_UID=$(stat -c '%u' "$AUTH_KEYS")

CURRENT_UID=$(id -u 2>/dev/null || echo "$HOME_UID")

# Ownership checks (allow current user UID or root 0)
if [ "$HOME_UID" -ne "$CURRENT_UID" ] && [ "$HOME_UID" -ne 0 ]; then
  fail "Server home directory $SERVER_HOME must be owned by the session user or root (current UID: $HOME_UID)."
fi
if [ "$SSH_UID" -ne "$CURRENT_UID" ] && [ "$SSH_UID" -ne 0 ]; then
  fail "Server .ssh directory $SERVER_SSH must be owned by the session user or root (current UID: $SSH_UID)."
fi
if [ "$KEYS_UID" -ne "$CURRENT_UID" ] && [ "$KEYS_UID" -ne 0 ]; then
  fail "Authorized keys file $AUTH_KEYS must be owned by the session user or root (current UID: $KEYS_UID)."
fi

# StrictModes check: must NOT be group-writable or other-writable (mode & 0022 == 0)
HOME_OCT=$((8#$HOME_MODE))
if [ $((HOME_OCT & 8#022)) -ne 0 ]; then
  fail "Server home directory has mode $HOME_MODE: group or others have write permissions, violating StrictModes."
fi

SSH_OCT=$((8#$SSH_MODE))
if [ $((SSH_OCT & 8#022)) -ne 0 ]; then
  fail "Server .ssh directory has mode $SSH_MODE: group or others have write permissions, violating StrictModes."
fi

KEYS_OCT=$((8#$KEYS_MODE))
if [ $((KEYS_OCT & 8#022)) -ne 0 ]; then
  fail "Authorized keys file has mode $KEYS_MODE: group or others have write permissions, violating StrictModes."
fi
