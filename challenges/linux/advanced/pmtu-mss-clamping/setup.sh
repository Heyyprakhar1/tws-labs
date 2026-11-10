#!/bin/bash
set -euo pipefail

INCIDENT_DIR="$HOME/pmtu-incident"
mkdir -p "$INCIDENT_DIR"/{bin,config,reports,traces}

# 1. Generate config/gateway.env
cat > "$INCIDENT_DIR/config/gateway.env" <<'EOF'
# Gateway Tunnel & Network Configuration
INTERFACE="gre0"
LOCAL_IP="10.100.1.10"
REMOTE_IP="10.200.2.20"
TUNNEL_MTU=1420
ETHERNET_MTU=1500
MSS_CLAMPING=disabled
TCP_MSS=1460
EOF

# 2. Generate config/iptables-rules.sh
cat > "$INCIDENT_DIR/config/iptables-rules.sh" <<'EOF'
#!/bin/bash
# Gateway Firewall & Traffic Shaping Rules
iptables -A FORWARD -i gre0 -j ACCEPT
iptables -A FORWARD -o gre0 -j ACCEPT

# TODO: Configure TCP MSS clamping for gre0 interface
# iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o gre0 -j TCPMSS --set-mss 1380
EOF
chmod +x "$INCIDENT_DIR/config/iptables-rules.sh"

# 3. Generate binary PCAP and text packet-stream.log via Python
python3 - <<'PYEOF'
import os
import struct

incident_dir = os.path.expanduser("~/pmtu-incident")
traces_dir = os.path.join(incident_dir, "traces")
pcap_path = os.path.join(traces_dir, "gateway-hang.pcap")
log_path = os.path.join(traces_dir, "packet-stream.log")

# Generate textual packet stream log
log_lines = [
    "=== Gateway Packet Capture: replication-sync.pcap ===",
    "Interface: gre0 (Tunnel MTU: 1420) | Ingress: eth0 (Ethernet MTU: 1500)",
    "",
    "No.  Time      Source         Destination    Proto  Len   Info",
    "--------------------------------------------------------------------------------",
    "  1  0.000000  10.100.1.10    10.200.2.20    TCP    74    48220 > 443 [SYN] Seq=0 Win=64240 Len=0 MSS=1460 Flags=[DF]",
    "  2  0.024100  10.200.2.20    10.100.1.10    TCP    74    443 > 48220 [SYN, ACK] Seq=0 Ack=1 Win=65160 Len=0 MSS=1460 Flags=[DF]",
    "  3  0.024250  10.100.1.10    10.200.2.20    TCP    54    48220 > 443 [ACK] Seq=1 Ack=1 Win=64240 Len=0 Flags=[DF]",
    "  4  0.025100  10.100.1.10    10.200.2.20    TLS    185   Client Hello (SNI=db-replica.partner.internal)",
    "  5  0.049200  10.200.2.20    10.100.1.10    TCP    54    443 > 48220 [ACK] Seq=1 Ack=132 Win=65160 Len=0 Flags=[DF]",
    "  6  0.050400  10.200.2.20    10.100.1.10    TLS    1500  Server Hello, Certificate [TCP segment of a reassembled PDU] Flags=[DF]",
    "  7  0.250800  10.200.2.20    10.100.1.10    TLS    1500  [TCP Retransmission] Server Hello, Certificate Flags=[DF]",
    "  8  0.651200  10.200.2.20    10.100.1.10    TLS    1500  [TCP Retransmission] Server Hello, Certificate Flags=[DF]",
    "  9  1.451600  10.200.2.20    10.100.1.10    TLS    1500  [TCP Retransmission] Server Hello, Certificate Flags=[DF]",
    " 10  3.052000  10.200.2.20    10.100.1.10    TLS    1500  [TCP Retransmission] Server Hello, Certificate Flags=[DF]",
    " 11  6.252400  10.200.2.20    10.100.1.10    TLS    1500  [TCP Retransmission] Server Hello, Certificate Flags=[DF]",
    "",
    "--- ICMP Feedback Analysis ---",
    "ICMP Type 3 Code 4 (Destination Unreachable / Fragmentation Needed): 0 received",
    "Status: Intermediate tunnel router dropped frame > 1420 bytes. Intermediate firewall blocked ICMP feedback.",
    "Result: Path MTU Discovery (PMTUD) Black Hole detected. Connection stalled indefinitely."
]

with open(log_path, "w") as f:
    f.write("\n".join(log_lines) + "\n")

# Generate binary PCAP
# PCAP global header: magic(4), v_maj(2), v_min(2), thiszone(4), sigfigs(4), snaplen(4), network(4)
global_hdr = struct.pack("<IHHiIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

packets = [
    (0, 0, 74, b"\x00"*14 + b"\x45\x00\x00\x3c\x1a\x2b\x40\x00\x40\x06\x00\x00\x0a\x64\x01\x0a\x0a\xc8\x02\x14" + b"\xbc\x5c\x01\xbb" + b"\x00"*36),
    (0, 24100, 74, b"\x00"*14 + b"\x45\x00\x00\x3c\x2b\x3c\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*36),
    (0, 24250, 54, b"\x00"*14 + b"\x45\x00\x00\x28\x3c\x4d\x40\x00\x40\x06\x00\x00\x0a\x64\x01\x0a\x0a\xc8\x02\x14" + b"\xbc\x5c\x01\xbb" + b"\x00"*16),
    (0, 25100, 185, b"\x00"*14 + b"\x45\x00\x00\xab\x4d\x5e\x40\x00\x40\x06\x00\x00\x0a\x64\x01\x0a\x0a\xc8\x02\x14" + b"\xbc\x5c\x01\xbb" + b"\x00"*147),
    (0, 49200, 54, b"\x00"*14 + b"\x45\x00\x00\x28\x5e\x6f\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*16),
    (0, 50400, 1500, b"\x00"*14 + b"\x45\x00\x05\xdc\x6f\x70\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*1462),
    (0, 250800, 1500, b"\x00"*14 + b"\x45\x00\x05\xdc\x70\x81\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*1462),
    (0, 651200, 1500, b"\x00"*14 + b"\x45\x00\x05\xdc\x71\x92\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*1462),
    (1, 451600, 1500, b"\x00"*14 + b"\x45\x00\x05\xdc\x72\xa3\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*1462),
    (3, 52000, 1500, b"\x00"*14 + b"\x45\x00\x05\xdc\x73\xb4\x40\x00\x40\x06\x00\x00\x0a\xc8\x02\x14\x0a\x64\x01\x0a" + b"\x01\xbb\xbc\x5c" + b"\x00"*1462),
]

with open(pcap_path, "wb") as f:
    f.write(global_hdr)
    for sec, usec, orig_len, data in packets:
        incl_len = len(data)
        pkt_hdr = struct.pack("<IIII", sec, usec, incl_len, orig_len)
        f.write(pkt_hdr + data)
PYEOF

# 4. Create bin/packet-analyzer
cat > "$INCIDENT_DIR/bin/packet-analyzer" <<'PYEOF'
#!/usr/bin/env python3
"""
Packet Analyzer CLI for PMTU Black Hole Forensics.
Parses packet traces and displays MTU, MSS, DF flags, and ICMP feedback.
"""
import os
import sys

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_FILE = os.path.join(INCIDENT_DIR, "traces", "packet-stream.log")
PCAP_FILE = os.path.join(INCIDENT_DIR, "traces", "gateway-hang.pcap")

def analyze():
    print("=== Packet Trace Forensic Analysis ===")
    print(f"Artifact Trace: {PCAP_FILE}")
    print(f"Decoded Stream: {LOG_FILE}\n")

    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            for line in f:
                if any(x in line for x in ["[SYN]", "Server Hello", "[TCP Retransmission]", "ICMP Type 3"]):
                    print("  " + line.strip())

    print("\n--- Forensic Summary ---")
    print("Negotiated TCP MSS:       1460 bytes")
    print("Dropped Frame Size:       1500 bytes")
    print("Don't Fragment (DF) Flag: SET (true)")
    print("ICMP Feedback Received:   0 packets (dropped by intermediate network)")
    print("Diagnostic Conclusion:    Path MTU Discovery Black Hole")
    print("Recommended Remediation:  Configure TCP MSS clamping (MSS = Tunnel MTU 1420 - 40 = 1380)")

if __name__ == "__main__":
    analyze()
PYEOF
chmod +x "$INCIDENT_DIR/bin/packet-analyzer"

# 5. Create bin/verify-transfer
cat > "$INCIDENT_DIR/bin/verify-transfer" <<'PYEOF'
#!/usr/bin/env python3
"""
Database Replication Transfer Simulator & Recovery Validator.
Validates gateway MSS clamping configuration against tunnel MTU.
"""
import os
import sys

INCIDENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(INCIDENT_DIR, "config", "gateway.env")
RULES_FILE = os.path.join(INCIDENT_DIR, "config", "iptables-rules.sh")
REPORT_FILE = os.path.join(INCIDENT_DIR, "reports", "recovery-report.env")

def read_config():
    config = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip().strip('"\'')
    return config

def check_rules():
    has_mss_rule = False
    if os.path.exists(RULES_FILE):
        with open(RULES_FILE) as f:
            content = f.read()
            if "TCPMSS" in content and ("--set-mss 1380" in content or "--clamp-mss-to-pmtu" in content):
                has_mss_rule = True
    return has_mss_rule

def run_verification(check_only=False):
    cfg = read_config()
    tunnel_mtu = int(cfg.get("TUNNEL_MTU", 1420))
    mss_clamping = cfg.get("MSS_CLAMPING", "disabled")
    tcp_mss = int(cfg.get("TCP_MSS", 1460))
    has_rule = check_rules()

    print("[*] Evaluating gateway MTU and MSS clamping configuration...")
    print(f"    Tunnel Interface MTU: {tunnel_mtu}")
    print(f"    MSS Clamping State:   {mss_clamping}")
    print(f"    Configured TCP MSS:   {tcp_mss}")
    print(f"    Firewall Mangle Rule: {'Configured' if has_rule else 'Missing'}")

    effective_frame_size = tcp_mss + 40

    if check_only:
        if mss_clamping == "enabled" and tcp_mss <= 1380 and has_rule:
            print("\n[OK] Gateway configuration is valid for tunnel traversal.")
            sys.exit(0)
        else:
            print("\n[FAIL] Configuration incomplete or invalid.")
            sys.exit(1)

    print("\n[*] Simulating 64 KB bulk database replication sync across gre0...")
    if mss_clamping != "enabled" or tcp_mss > 1380 or not has_rule:
        print(f"\n[FAIL] Packet drop detected on tunnel boundary:")
        print(f"       Segment size ({tcp_mss}) + headers (40) = {effective_frame_size} bytes.")
        print(f"       Frame size {effective_frame_size} exceeds gre0 MTU ({tunnel_mtu}).")
        print(f"       DF bit is set; intermediate tunnel drops frame without ICMP feedback.")
        print(f"       Result: Transfer stalled. Connection timed out after 5 retransmissions.")
        sys.exit(1)
    else:
        # Transfer succeeds
        segments = 48
        print(f"\n[PASS] Bulk transfer succeeded:")
        print(f"       Clamped MSS: {tcp_mss} bytes payload.")
        print(f"       Effective frame size: {effective_frame_size} bytes <= tunnel MTU {tunnel_mtu}.")
        print(f"       Transmitted {segments} segments without fragmentation or loss.")

        os.makedirs(os.path.dirname(REPORT_FILE), exist_ok=True)
        with open(REPORT_FILE, "w") as f:
            f.write("TRANSFER_STATUS=SUCCESS\n")
            f.write(f"SEGMENTS_TRANSMITTED={segments}\n")
            f.write(f"MAX_SEGMENT_SIZE={tcp_mss}\n")
            f.write(f"EFFECTIVE_FRAME_SIZE={effective_frame_size}\n")
            f.write("PACKET_LOSS_COUNT=0\n")
        print(f"       Recovery report written to reports/recovery-report.env.")
        sys.exit(0)

if __name__ == "__main__":
    check_only = "--check-config" in sys.argv
    run_verification(check_only=check_only)
PYEOF
chmod +x "$INCIDENT_DIR/bin/verify-transfer"
