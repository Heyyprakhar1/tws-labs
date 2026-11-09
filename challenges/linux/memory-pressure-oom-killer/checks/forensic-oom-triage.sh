. "$LAB_LIB"

REPORT="mem-incident/reports/oom-forensics.env"
[ -f "$REPORT" ] || fail "Report mem-incident/reports/oom-forensics.env does not exist."

INCIDENT_TIME=$(grep -E '^[[:space:]]*INCIDENT_TIMESTAMP=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CGROUP_VER=$(grep -E '^[[:space:]]*CGROUP_VERSION=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
TRIGGER_PROC=$(grep -E '^[[:space:]]*TRIGGER_PROCESS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
TRIGGER_PID=$(grep -E '^[[:space:]]*TRIGGER_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
KILLED_PROC=$(grep -E '^[[:space:]]*KILLED_PROCESS=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
KILLED_PID=$(grep -E '^[[:space:]]*KILLED_PID=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
KILLED_RSS=$(grep -E '^[[:space:]]*KILLED_ANON_RSS_KB=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CGROUP_MAX=$(grep -E '^[[:space:]]*CGROUP_MAX_BYTES=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CGROUP_OOM=$(grep -E '^[[:space:]]*CGROUP_OOM_COUNT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
CGROUP_KILL=$(grep -E '^[[:space:]]*CGROUP_OOM_KILL_COUNT=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)
OOM_PROVEN=$(grep -E '^[[:space:]]*OOM_PROVEN=' "$REPORT" | head -n1 | cut -d= -f2- | tr -d '[:space:]"' || true)

[ "$INCIDENT_TIME" = "08:42:14UTC" ] || [ "$INCIDENT_TIME" = "08:42:14" ] || fail "INCIDENT_TIMESTAMP must be 08:42:14 UTC (got '$INCIDENT_TIME')."
[ "$CGROUP_VER" = "v2" ] || fail "CGROUP_VERSION must be v2 (got '$CGROUP_VER')."
[ "$TRIGGER_PROC" = "data-aggregator-ingest" ] || fail "TRIGGER_PROCESS must be data-aggregator-ingest (got '$TRIGGER_PROC')."
[ "$TRIGGER_PID" = "4128" ] || fail "TRIGGER_PID must be 4128 (got '$TRIGGER_PID')."
[ "$KILLED_PROC" = "data-aggregator-worker" ] || fail "KILLED_PROCESS must be data-aggregator-worker (got '$KILLED_PROC')."
[ "$KILLED_PID" = "4129" ] || fail "KILLED_PID must be 4129 (got '$KILLED_PID')."
[ "$KILLED_RSS" = "248320" ] || fail "KILLED_ANON_RSS_KB must be 248320 (got '$KILLED_RSS')."
[ "$CGROUP_MAX" = "268435456" ] || fail "CGROUP_MAX_BYTES must be 268435456 (got '$CGROUP_MAX')."
[ "$CGROUP_OOM" = "1" ] || fail "CGROUP_OOM_COUNT must be 1 (got '$CGROUP_OOM')."
[ "$CGROUP_KILL" = "1" ] || fail "CGROUP_OOM_KILL_COUNT must be 1 (got '$CGROUP_KILL')."
[ "$OOM_PROVEN" = "true" ] || fail "OOM_PROVEN must be true (got '$OOM_PROVEN')."
