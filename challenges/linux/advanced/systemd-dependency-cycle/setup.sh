#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/systemd-incident"
mkdir -p "$INCIDENT_DIR"/{bin,config/units,reports,logs,var/run}

# 1. Generate unit files in config/units/
cat > "$INCIDENT_DIR/config/units/payment-api.service" <<'EOF'
[Unit]
Description=Payment API Gateway
Requires=payment-db.service
After=payment-db.service payment-cache.service

[Service]
ExecStart=/bin/echo "Starting payment-api"
EOF

cat > "$INCIDENT_DIR/config/units/payment-cache.service" <<'EOF'
[Unit]
Description=Payment Redis Cache
Wants=payment-auth.service
After=payment-auth.service

[Service]
ExecStart=/bin/echo "Starting payment-cache"
EOF

cat > "$INCIDENT_DIR/config/units/payment-auth.service" <<'EOF'
[Unit]
Description=Payment Authentication Service
Requires=payment-api.service
After=payment-api.service

[Service]
ExecStart=/bin/echo "Starting payment-auth"
EOF

cat > "$INCIDENT_DIR/config/units/payment-db.service" <<'EOF'
[Unit]
Description=Payment PostgreSQL Database
Before=payment-cache.service

[Service]
ExecStart=/bin/echo "Starting payment-db"
EOF

# 2. Create bin/systemd-analyze (Python DAG Validator)
cat > "$INCIDENT_DIR/bin/systemd-analyze" <<'PYEOF'
#!/usr/bin/env python3
"""
Systemd DAG Dependency & Ordering Cycle Analyzer.
Implements Kahn's topological sort algorithm to validate service dependency graphs.
"""
import os
import sys
from collections import defaultdict, deque

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNITS_DIR = os.path.join(INCIDENT_DIR, "config", "units")

def parse_units():
    units = {}
    if not os.path.exists(UNITS_DIR):
        return units

    for fname in sorted(os.listdir(UNITS_DIR)):
        if not fname.endswith(".service"):
            continue
        unit_path = os.path.join(UNITS_DIR, fname)
        props = {
            "name": fname,
            "Description": fname,
            "After": [],
            "Before": [],
            "Requires": [],
            "Wants": []
        }
        with open(unit_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("["):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    k, v = k.strip(), v.strip()
                    if k in ["After", "Before", "Requires", "Wants"]:
                        props[k].extend(v.split())
                    elif k == "Description":
                        props["Description"] = v
        units[fname] = props
    return units

def build_ordering_graph(units):
    """
    Build directed graph of execution order:
    Edge (u -> v) means 'u must execute before v'.
    - If v has 'After=u', add edge (u -> v).
    - If u has 'Before=v', add edge (u -> v).
    """
    nodes = set(units.keys())
    adj = defaultdict(set)
    in_degree = {node: 0 for node in nodes}

    for name, props in units.items():
        # After: u must run before name (u -> name)
        for u in props["After"]:
            if u in nodes and u != name:
                if name not in adj[u]:
                    adj[u].add(name)
                    in_degree[name] += 1

        # Before: name must run before v (name -> v)
        for v in props["Before"]:
            if v in nodes and v != name:
                if v not in adj[name]:
                    adj[name].add(v)
                    in_degree[v] += 1

    return nodes, adj, in_degree

def find_cycle(nodes, adj, in_degree):
    """
    Kahn's topological sort algorithm.
    Returns (is_cyclic, order_or_cycle_units)
    """
    deg = dict(in_degree)
    queue = deque([u for u in nodes if deg[u] == 0])
    topo_order = []

    while queue:
        u = queue.popleft()
        topo_order.append(u)
        for v in sorted(adj[u]):
            deg[v] -= 1
            if deg[v] == 0:
                queue.append(v)

    if len(topo_order) == len(nodes):
        return False, topo_order

    # Cycle detected: nodes remaining with in-degree > 0
    cycle_nodes = [u for u in nodes if deg[u] > 0]
    return True, sorted(cycle_nodes)

def verify():
    units = parse_units()
    if not units:
        print("[ERROR] No unit files found in config/units/")
        sys.exit(1)

    nodes, adj, in_degree = build_ordering_graph(units)
    is_cyclic, result = find_cycle(nodes, adj, in_degree)

    if is_cyclic:
        print("systemd[1]: Found ordering cycle on payment-api.service:")
        print("  payment-api.service -> After -> payment-cache.service")
        print("  payment-cache.service -> After -> payment-auth.service")
        print("  payment-auth.service -> After -> payment-api.service")
        print("\nsystemd[1]: Breaking ordering cycle by deleting job payment-db.service")
        print("systemd[1]: Job payment-db.service/start deleted to break ordering cycle.")
        print(f"\n[FAIL] Ordering cycle detected across {len(result)} units:")
        for u in result:
            print(f"  - {u}")
        print("\nHint: Check After= and Before= directives in config/units/ to eliminate circular ordering.")
        sys.exit(1)
    else:
        print("Verification successful: 0 cycles detected. Valid DAG ordering verified.")
        print("\nComputed Topological Execution Order:")
        for idx, u in enumerate(result, 1):
            print(f"  [{idx}/{len(result)}] {u}")
        sys.exit(0)

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if cmd == "verify":
        verify()
    elif cmd == "dump":
        units = parse_units()
        for name, p in units.items():
            print(f"[{name}]")
            print(f"  Description: {p['Description']}")
            print(f"  Requires:    {', '.join(p['Requires']) or 'none'}")
            print(f"  Wants:       {', '.join(p['Wants']) or 'none'}")
            print(f"  After:       {', '.join(p['After']) or 'none'}")
            print(f"  Before:      {', '.join(p['Before']) or 'none'}\n")
    else:
        print(f"Usage: {sys.argv[0]} [verify|dump]")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INCIDENT_DIR/bin/systemd-analyze"

# 3. Create bin/systemctl (Python Service Controller Shim)
cat > "$INCIDENT_DIR/bin/systemctl" <<'PYEOF'
#!/usr/bin/env python3
"""
Systemctl Unit Controller Shim for DAG Challenge.
Executes topological startup transactions and manages service state.
"""
import os
import sys
import subprocess

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANALYZE_BIN = os.path.join(INCIDENT_DIR, "bin", "systemd-analyze")
REPORT_FILE = os.path.join(INCIDENT_DIR, "reports", "recovery-report.env")
STATE_FILE = os.path.join(INCIDENT_DIR, "var", "run", "active-units.txt")

def start_unit(target):
    # 1. Run DAG validation
    res = subprocess.run([ANALYZE_BIN, "verify"], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Failed to start {target}: Ordering cycle detected.")
        print(res.stdout.strip())
        sys.exit(1)

    # 2. Extract topological order from output
    order = []
    for line in res.stdout.splitlines():
        if "[" in line and "]" in line and ".service" in line:
            parts = line.split()
            if len(parts) >= 2 and parts[1].endswith(".service"):
                order.append(parts[1])

    if not order:
        order = ["payment-db.service", "payment-auth.service", "payment-cache.service", "payment-api.service"]

    print(f"Executing startup transaction for {target} ({len(order)} units)...")
    for idx, u in enumerate(order, 1):
        print(f"  [{idx}/{len(order)}] Starting {u}... done.")

    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        f.write("\n".join(order) + "\n")

    os.makedirs(os.path.dirname(REPORT_FILE), exist_ok=True)
    with open(REPORT_FILE, "w") as f:
        f.write("STARTUP_STATUS=SUCCESS\n")
        f.write(f"ACTIVATED_UNITS={len(order)}\n")
        f.write(f'TOPOLOGICAL_ORDER="{",".join(order)}"\n')
        f.write("CYCLES_COUNT=0\n")

    print(f"\nStartup complete. All {len(order)} units active in valid topological order.")
    print("Recovery report written to reports/recovery-report.env.")
    sys.exit(0)

def status_unit(target):
    if not target.endswith(".service"):
        target += ".service"
    active_units = set()
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            active_units = {l.strip() for l in f if l.strip()}

    if target in active_units:
        print(f"● {target} - Payment Service Component")
        print("     Loaded: loaded (/config/units/" + target + ")")
        print("     Active: active (running)")
    else:
        # Check if cycle currently prevents startup
        res = subprocess.run([ANALYZE_BIN, "verify"], capture_output=True, text=True)
        print(f"● {target} - Payment Service Component")
        print("     Loaded: loaded (/config/units/" + target + ")")
        if res.returncode != 0:
            print("     Active: failed (Result: ordering-cycle)")
            print("     Error: systemd[1]: Found ordering cycle on " + target)
        else:
            print("     Active: inactive (dead)")

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} [status|start|stop] <unit>")
        sys.exit(1)
    cmd = sys.argv[1]
    target = sys.argv[2] if len(sys.argv) > 2 else "payment-api.service"

    if cmd == "start":
        start_unit(target)
    elif cmd == "status":
        status_unit(target)
    elif cmd == "stop":
        if os.path.exists(STATE_FILE):
            os.remove(STATE_FILE)
        print(f"Stopped {target} and associated units.")
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INCIDENT_DIR/bin/systemctl"
