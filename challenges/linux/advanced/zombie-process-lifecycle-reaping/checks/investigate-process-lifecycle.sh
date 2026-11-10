#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/zombie-incident"
REPORT="$INCIDENT_DIR/reports/lifecycle-analysis.env"

if [ ! -f "$REPORT" ]; then
    echo "Check failed: reports/lifecycle-analysis.env not found."
    exit 1
fi

REQUIRED_SIGNAL=$(grep '^REQUIRED_SIGNAL=' "$REPORT" | cut -d= -f2- | tr -d ' "')
REAP_SYSCALL=$(grep '^REAP_SYSCALL=' "$REPORT" | cut -d= -f2- | tr -d ' "')
WAITPID_FLAGS=$(grep '^WAITPID_FLAGS=' "$REPORT" | cut -d= -f2- | tr -d ' "')
LOOP_STRATEGY=$(grep '^LOOP_STRATEGY=' "$REPORT" | cut -d= -f2- | tr -d ' "')

if [ "$REQUIRED_SIGNAL" != "SIGCHLD" ]; then
    echo "Check failed: REQUIRED_SIGNAL expected SIGCHLD, got '$REQUIRED_SIGNAL'."
    exit 1
fi

if [ "$REAP_SYSCALL" != "waitpid" ]; then
    echo "Check failed: REAP_SYSCALL expected waitpid, got '$REAP_SYSCALL'."
    exit 1
fi

if [ "$WAITPID_FLAGS" != "WNOHANG" ]; then
    echo "Check failed: WAITPID_FLAGS expected WNOHANG, got '$WAITPID_FLAGS'."
    exit 1
fi

if [ "$LOOP_STRATEGY" != "WHILE_POSITIVE_PID" ]; then
    echo "Check failed: LOOP_STRATEGY expected WHILE_POSITIVE_PID, got '$LOOP_STRATEGY'."
    exit 1
fi

echo "Check passed: Linux process lifecycle and SIGCHLD reaping mechanics analyzed."
exit 0
