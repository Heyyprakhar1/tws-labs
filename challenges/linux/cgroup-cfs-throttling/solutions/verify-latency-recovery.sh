#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/cgroup-incident"
"$INCIDENT_DIR/bin/benchmark-latency"
