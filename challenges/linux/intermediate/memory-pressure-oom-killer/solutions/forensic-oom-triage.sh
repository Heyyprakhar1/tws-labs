#!/bin/bash
set -euo pipefail

BASE="mem-incident"
mkdir -p "$BASE/reports"

cat << 'EOF' > "$BASE/reports/oom-forensics.env"
INCIDENT_TIMESTAMP=08:42:14 UTC
CGROUP_VERSION=v2
OOM_EVIDENCE_SOURCE=kernel log and cgroup memory.events
TRIGGER_PROCESS=data-aggregator-ingest
TRIGGER_PID=4128
KILLED_PROCESS=data-aggregator-worker
KILLED_PID=4129
KILLED_ANON_RSS_KB=248320
CGROUP_MAX_BYTES=268435456
CGROUP_OOM_COUNT=1
CGROUP_OOM_KILL_COUNT=1
OOM_PROVEN=true
EOF
