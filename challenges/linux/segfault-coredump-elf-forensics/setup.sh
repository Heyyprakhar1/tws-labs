#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
mkdir -p "$TARGET_DIR/artifacts" "$TARGET_DIR/bin" "$TARGET_DIR/src" "$TARGET_DIR/config" "$TARGET_DIR/reports"

# 1. Synthesize genuine 64-bit ELF binary (worker_service) and Core Dump (core.worker_service.12480)
python3 -c '
import struct
import hashlib
import os

target_dir = os.environ.get("TARGET_DIR", os.path.expanduser("~/segfault-incident"))
art_dir = os.path.join(target_dir, "artifacts")
os.makedirs(art_dir, exist_ok=True)

# -------------------------------------------------------------
# 1. Synthesize ELF Executable: worker_service
# -------------------------------------------------------------
# e_ident: \x7fELF, 2 (64-bit), 1 (LSB), 1 (EV_CURRENT), 0 (SYSV), 0 (abi ver), 7 bytes padding
e_ident = b"\x7fELF\x02\x01\x01\x00\x00" + b"\x00"*7

# Build ID Note (NT_GNU_BUILD_ID = 3)
note_owner = b"GNU\x00"
build_id_hex = "b84f93a1c29e6123456789abcdef0123456789ab"
build_id_bytes = bytes.fromhex(build_id_hex)
nhdr_buildid = struct.pack("<III", len(note_owner), len(build_id_bytes), 3)
note_buildid_data = nhdr_buildid + note_owner + build_id_bytes

# Text section bytes at offset 0x1000
# At offset 0x1e0: xor %rax, %rax (48 31 c0)
# At offset 0x1e4: movq (%rax), %rdx (48 8b 10) followed by ret (c3)
text_data = bytearray(4096)
text_data[0x1e0:0x1e7] = b"\x48\x31\xc0\x48\x8b\x10\xc3"

# ELF Header: ET_EXEC (2), EM_X86_64 (62), entry = 0x55d7a81211e0, phoff = 64, phnum = 2
ehdr_elf = e_ident + struct.pack("<HHIQQQIHHHHHH", 2, 62, 1, 0x55d7a81211e0, 64, 0, 0, 64, 56, 2, 0, 0, 0)

# Program Header 0: PT_LOAD (1), PF_R|PF_W|PF_X (7), offset 0, vaddr 0x55d7a8120000, paddr 0x55d7a8120000, filesz 0x2000, memsz 0x2000, align 0x1000
phdr0_load = struct.pack("<IIQQQQQQ", 1, 7, 0, 0x55d7a8120000, 0x55d7a8120000, 0x2000, 0x2000, 0x1000)

# Program Header 1: PT_NOTE (4), PF_R (4), offset 64 + 56*2 = 176, vaddr 0x55d7a8120000 + 176, paddr 0x55d7a8120000 + 176, len(note_buildid_data), len(note_buildid_data), 4
note_offset = 64 + 56*2
phdr1_note = struct.pack("<IIQQQQQQ", 4, 4, note_offset, 0x55d7a8120000 + note_offset, 0x55d7a8120000 + note_offset, len(note_buildid_data), len(note_buildid_data), 4)

elf_bytes = bytearray(ehdr_elf + phdr0_load + phdr1_note + note_buildid_data)
# Pad to 0x1000 boundary for text segment
if len(elf_bytes) < 0x1000:
    elf_bytes.extend(b"\x00" * (0x1000 - len(elf_bytes)))
elf_bytes.extend(text_data)

exe_path = os.path.join(art_dir, "worker_service")
with open(exe_path, "wb") as f:
    f.write(elf_bytes)
os.chmod(exe_path, 0o755)

# Calculate SHA256 of the binary for provenance
sha256_hash = hashlib.sha256(elf_bytes).hexdigest()
with open(os.path.join(art_dir, "build-provenance.env"), "w") as f:
    f.write(f"BUILD_ID={build_id_hex}\n")
    f.write(f"EXECUTABLE_SHA256={sha256_hash}\n")
    f.write("TOOLCHAIN=gcc-12.2.0-x86_64-linux-gnu\n")
    f.write("LINK_FLAGS=\"-Wl,--build-id=sha1 -pie\"\n")

# -------------------------------------------------------------
# 2. Synthesize ELF Core Dump: core.worker_service.12480
# -------------------------------------------------------------
# Note 1: NT_PRPSINFO (type 3, 136 bytes descriptor)
# prpsinfo_t: state, sname, zomb, nice, 4 bytes pad, flag, uid, gid, pid, ppid, pgrp, sid, fname, psargs
prpsinfo_desc = struct.pack("<BBBB4xQIIiiii16s80s", 0, ord("R"), 0, 0, 0, 10000, 10000, 12480, 12400, 12480, 12480, b"worker_service\x00", b"./worker_service --batch\x00")
note_name_core = b"CORE\x00\x00\x00\x00" # 4 chars + null padded to 8 bytes
nhdr_prpsinfo = struct.pack("<III", 5, len(prpsinfo_desc), 3)
note_prpsinfo_chunk = nhdr_prpsinfo + note_name_core + prpsinfo_desc

# Note 2: NT_PRSTATUS (type 1, 336 bytes descriptor)
# struct elf_prstatus:
# pr_info: si_signo (int), si_code (int), si_errno (int) = (11, 1, 0) (12 bytes)
# pr_cursig: 11 (int16), pad: 2 bytes
# pr_sigpend: 0 (uint64), pr_sighold: 0 (uint64)
# pr_pid: 12480, pr_ppid: 12400, pr_pgrp: 12480, pr_sid: 12480 (16 bytes)
# 4 x timeval (utime, stime, cutime, cstime) = 4 * 16 = 64 bytes
# pr_reg: user_regs_struct (27 uint64 fields = 216 bytes)
#   r15, r14, r13, r12, rbp, rbx, r11, r10, r9, r8, rax, rcx, rdx, rsi, rdi, orig_rax, rip, cs, eflags, rsp, ss, fs_base, gs_base, ds, es, fs, gs
#   rax = 0x0
#   rip = 0x000055d7a81211e4
#   rsp = 0x00007ffc6422b310
#   rbp = 0x00007ffc6422b350
#   eflags = 0x10206
# pr_fpvalid: 1 (int32), pad: 4 bytes
# Total descriptor size = 12 + 4 + 16 + 16 + 64 + 216 + 8 = 336 bytes
regs = [
    0, 0, 0, 0,                     # r15..r12
    0x00007ffc6422b350, 0,          # rbp, rbx
    0, 0, 0, 0,                     # r11..r8
    0x0000000000000000,             # rax (0x0, crashing register!)
    0, 0, 0, 0, 0,                  # rcx, rdx, rsi, rdi, orig_rax
    0x000055d7a81211e4,             # rip (faulting instruction counter!)
    0x33,                           # cs
    0x10206,                        # eflags
    0x00007ffc6422b310,             # rsp
    0x2b,                           # ss
    0, 0, 0, 0, 0, 0                # fs_base, gs_base, ds, es, fs, gs
]
pr_reg_bytes = struct.pack("<27Q", *regs)
prstatus_desc = struct.pack("<iiiHHQQiiiiQQQQQQQQ",
    11, 1, 0,                       # pr_info: si_signo=11, si_code=1, si_errno=0
    11, 0,                          # pr_cursig=11, pad
    0, 0,                           # sigpend, sighold
    12480, 12400, 12480, 12480,     # pid, ppid, pgrp, sid
    0, 0, 0, 0, 0, 0, 0, 0          # 4 x timeval (utime, stime, cutime, cstime)
) + pr_reg_bytes + struct.pack("<ii", 1, 0) # fpvalid, pad

nhdr_prstatus = struct.pack("<III", 5, len(prstatus_desc), 1)
note_prstatus_chunk = nhdr_prstatus + note_name_core + prstatus_desc

# Note 3: NT_SIGINFO (type 0x53494749 = 1397249865, 128 bytes descriptor)
# siginfo_t: si_signo (int32), si_errno (int32), si_code (int32)
# pad: 4 bytes
# si_addr: uint64 (at offset 16)
siginfo_desc = bytearray(128)
siginfo_desc[0:4] = struct.pack("<i", 11)                   # si_signo = 11 (SIGSEGV)
siginfo_desc[4:8] = struct.pack("<i", 0)                    # si_errno = 0
siginfo_desc[8:12] = struct.pack("<i", 1)                   # si_code = 1 (SEGV_MAPERR)
siginfo_desc[16:24] = struct.pack("<Q", 0x0000000000000000) # si_addr = 0x0
nhdr_siginfo = struct.pack("<III", 5, len(siginfo_desc), 0x53494749)
note_siginfo_chunk = nhdr_siginfo + note_name_core + bytes(siginfo_desc)

# Note 4: NT_FILE (type 10, mapped files)
# long count, long page_size
# struct { long start, end, file_ofs } map[count]
# filenames
fname_str = f"{art_dir}/worker_service\x00".encode("utf-8")
count = 1
page_size = 4096
nt_file_desc = struct.pack("<QQQQQ", count, page_size, 0x55d7a8121000, 0x55d7a8122000, 0) + fname_str
# pad descriptor to 4-byte boundary
if len(nt_file_desc) % 4 != 0:
    nt_file_desc += b"\x00" * (4 - (len(nt_file_desc) % 4))
nhdr_file = struct.pack("<III", 5, len(nt_file_desc), 10)
note_file_chunk = nhdr_file + note_name_core + nt_file_desc

all_notes = note_prpsinfo_chunk + note_prstatus_chunk + note_siginfo_chunk + note_file_chunk

# Core ELF Header: ET_CORE (4), EM_X86_64 (62), phoff = 64, phnum = 2 (PT_NOTE, PT_LOAD)
ehdr_core = e_ident + struct.pack("<HHIQQQIHHHHHH", 4, 62, 1, 0, 64, 0, 0, 64, 56, 2, 0, 0, 0)

# Program Headers:
# Phdr 0: PT_NOTE (4), offset 64 + 56*2 = 176, vaddr 0, filesz len(all_notes), memsz 0, align 4
core_note_offset = 64 + 56*2
core_phdr0_note = struct.pack("<IIQQQQQQ", 4, 0, core_note_offset, 0, 0, len(all_notes), 0, 4)

# Phdr 1: PT_LOAD (1), offset = core_note_offset + len(all_notes), vaddr = 0x55d7a8121000, filesz = 4096, memsz = 4096, align 4096
core_load_offset = core_note_offset + len(all_notes)
if core_load_offset % 4096 != 0:
    core_load_offset = (core_load_offset + 4095) & ~4095
core_phdr1_load = struct.pack("<IIQQQQQQ", 1, 5, core_load_offset, 0x55d7a8121000, 0x55d7a8121000, 4096, 4096, 4096)

core_bytes = bytearray(ehdr_core + core_phdr0_note + core_phdr1_load + all_notes)
if len(core_bytes) < core_load_offset:
    core_bytes.extend(b"\x00" * (core_load_offset - len(core_bytes)))
core_bytes.extend(text_data)

core_path = os.path.join(art_dir, "core.worker_service.12480")
with open(core_path, "wb") as f:
    f.write(core_bytes)
os.chmod(core_path, 0o644)
'

# 2. Write kernel crash log
cat << 'EOF' > "$TARGET_DIR/artifacts/dmesg-crash.log"
[  142.891230] worker_service[12480]: segfault at 0 ip 000055d7a81211e4 sp 00007ffc6422b310 error 4 in worker_service[55d7a8121000+1000] likely on CPU 2 (core 1, socket 0)
[  142.891238] Code: 48 89 5d e8 48 8b 45 f8 48 8b 40 18 48 85 c0 74 12 48 8b 45 f8 48 8b 40 18 48 8b 00 <48> 8b 10 48 89 d6 48 89 c7 e8 d4 fe ff ff
EOF

# 3. Write C source code
cat << 'EOF' > "$TARGET_DIR/src/worker_service.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

typedef struct {
    char *host;
    int port;
} telemetry_endpoint_t;

typedef struct {
    int batch_size;
    int concurrency;
    bool telemetry_enabled;
    telemetry_endpoint_t *telemetry_endpoint;
} worker_config_t;

typedef struct {
    int record_id;
    char payload[256];
} batch_record_t;

void dispatch_telemetry(const char *endpoint_host, const batch_record_t *rec) {
    printf("[telemetry] dispatched metric for record %d to %s\n", rec->record_id, endpoint_host);
}

void process_batch(worker_config_t *config, batch_record_t *records, int count) {
    for (int i = 0; i < count; i++) {
        // Record processing
        records[i].record_id = i + 1;
        snprintf(records[i].payload, sizeof(records[i].payload), "record_payload_%d", i + 1);

        if (config->telemetry_enabled) {
            /* 
             * DEFECT: telemetry_endpoint is dereferenced directly without verifying
             * if config->telemetry_endpoint != NULL.
             * When TELEMETRY_ENDPOINT is not provided in worker.env,
             * telemetry_endpoint is NULL (0x0). Dereferencing it triggers a page fault
             * with error code 4 (user read of non-present page), raising SIGSEGV.
             */
            const char *host = config->telemetry_endpoint->host; // <-- SEGFAULT AT 0x0
            dispatch_telemetry(host, &records[i]);
        }
    }
}

int main(int argc, char **argv) {
    worker_config_t cfg = {
        .batch_size = 100,
        .concurrency = 4,
        .telemetry_enabled = true,
        .telemetry_endpoint = NULL // Uninitialized fallback
    };
    batch_record_t batch[100];
    process_batch(&cfg, batch, 100);
    return 0;
}
EOF

# 4. Write worker configuration (initial crashing state)
cat << 'EOF' > "$TARGET_DIR/config/worker.env"
# Production Batch Worker Configuration
BATCH_SIZE=100
WORKER_CONCURRENCY=4
DATABASE_URL="postgres://app:secret@db.internal:5432/batches"
TELEMETRY_ENABLED="true"
# TELEMETRY_ENDPOINT is omitted, causing config->telemetry_endpoint to remain NULL
EOF

# 5. Create bin/coredump-analyzer (Pure Python raw byte parser)
cat << 'EOF' > "$TARGET_DIR/bin/coredump-analyzer"
#!/usr/bin/env python3
import sys
import os
import struct

def parse_core(filepath):
    if not os.path.exists(filepath):
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    with open(filepath, "rb") as f:
        data = f.read()

    filesize = len(data)
    if filesize < 64:
        print("Error: truncated ELF header (less than 64 bytes)", file=sys.stderr)
        sys.exit(1)

    # Validate ELF magic
    if data[0:4] != b"\x7fELF":
        print("Error: invalid ELF magic", file=sys.stderr)
        sys.exit(1)

    elf_class = data[4]
    data_enc = data[5]
    if elf_class != 2 or data_enc != 1:
        print("Error: only 64-bit Little-Endian (ELFCLASS64, 2LSB) is supported", file=sys.stderr)
        sys.exit(1)

    # Parse Elf64_Ehdr
    e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum = struct.unpack("<HHIQQQIHHH", data[16:58])
    if e_type != 4:
        print(f"Error: expected ELF core file (ET_CORE=4), got e_type={e_type}", file=sys.stderr)
        sys.exit(1)

    # Bounds check Program Headers
    if e_phoff + (e_phnum * e_phentsize) > filesize:
        print("Error: program header table extends beyond file size", file=sys.stderr)
        sys.exit(1)

    notes = []
    # Iterate Program Headers to find PT_NOTE (type 4)
    for i in range(e_phnum):
        off = e_phoff + (i * e_phentsize)
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack("<IIQQQQQQ", data[off:off+56])
        if p_type == 4: # PT_NOTE
            note_data = data[p_offset:p_offset+p_filesz]
            # Parse notes inside note_data
            n_off = 0
            while n_off + 12 <= len(note_data):
                n_namesz, n_descsz, n_type = struct.unpack("<III", note_data[n_off:n_off+12])
                n_off += 12
                # Note name padded to 4 bytes
                name_padded_sz = (n_namesz + 3) & ~3
                desc_padded_sz = (n_descsz + 3) & ~3
                if n_off + name_padded_sz + desc_padded_sz > len(note_data):
                    break
                name = note_data[n_off:n_off+n_namesz].rstrip(b"\x00").decode("utf-8", errors="ignore")
                n_off += name_padded_sz
                desc = note_data[n_off:n_off+n_descsz]
                n_off += desc_padded_sz
                notes.append({
                    "type": n_type,
                    "name": name,
                    "desc": desc
                })

    return {
        "filesize": filesize,
        "elf_class": "ELF64" if elf_class == 2 else "ELF32",
        "data_encoding": "2LSB" if data_enc == 1 else "2MSB",
        "architecture": "x86_64" if e_machine == 62 else str(e_machine),
        "notes": notes
    }

def print_info(res):
    print(f"ELF Class: {res['elf_class']}")
    print(f"Data Encoding: {res['data_encoding']}")
    print(f"Architecture: {res['architecture']}")
    
    # Process name from NT_PRPSINFO
    for n in res["notes"]:
        if n["type"] == 3: # NT_PRPSINFO
            # fname is at offset 40, length 16
            fname = n["desc"][40:56].split(b"\x00")[0].decode("utf-8", errors="ignore")
            # psargs at offset 56, length 80
            psargs = n["desc"][56:136].split(b"\x00")[0].decode("utf-8", errors="ignore")
            print(f"Process Name: {fname}")
            print(f"Process Arguments: {psargs}")
        elif n["type"] == 1: # NT_PRSTATUS
            pid = struct.unpack("<i", n["desc"][32:36])[0]
            sig = struct.unpack("<H", n["desc"][12:14])[0]
            signame = "SIGSEGV" if sig == 11 else f"Signal {sig}"
            print(f"Crashed PID: {pid}")
            print(f"Terminating Signal: {signame} ({sig})")
            print(f"Conventional Shell Status: {128 + sig}")

def print_registers(res):
    for n in res["notes"]:
        if n["type"] == 1: # NT_PRSTATUS
            # Register array starts at offset 112 (27 uint64 fields)
            regs_raw = struct.unpack("<27Q", n["desc"][112:112+216])
            rax = regs_raw[10]
            rbx = regs_raw[5]
            rcx = regs_raw[11]
            rdx = regs_raw[12]
            rsi = regs_raw[13]
            rdi = regs_raw[14]
            rbp = regs_raw[4]
            rsp = regs_raw[19]
            rip = regs_raw[16]
            eflags = regs_raw[18]

            print("General Purpose Registers:")
            print(f"  rip: 0x{rip:016x}")
            print(f"  rsp: 0x{rsp:016x}")
            print(f"  rbp: 0x{rbp:016x}")
            print(f"  rax: 0x{rax:016x}")
            print(f"  rbx: 0x{rbx:016x}")
            print(f"  rcx: 0x{rcx:016x}")
            print(f"  rdx: 0x{rdx:016x}")
            print(f"  rsi: 0x{rsi:016x}")
            print(f"  rdi: 0x{rdi:016x}")
            print(f"  eflags: 0x{eflags:08x}")
            return
    print("Error: NT_PRSTATUS note not found", file=sys.stderr)

def print_siginfo(res):
    for n in res["notes"]:
        if n["type"] == 0x53494749: # NT_SIGINFO
            signo, errno, code = struct.unpack("<iii", n["desc"][0:12])
            si_addr = struct.unpack("<Q", n["desc"][16:24])[0]
            code_name = "SEGV_MAPERR" if code == 1 else "SEGV_ACCERR" if code == 2 else f"Code {code}"
            print(f"Signal Number: {signo} (SIGSEGV)")
            print(f"Signal Code: {code} ({code_name})")
            print(f"Fault Address (si_addr): 0x{si_addr:x}")
            return
    print("Error: NT_SIGINFO note not found", file=sys.stderr)

def print_maps(res):
    for n in res["notes"]:
        if n["type"] == 10: # NT_FILE
            count, page_size = struct.unpack("<QQ", n["desc"][0:16])
            print(f"Mapped Files ({count} entries, page size {page_size}):")
            offset = 16
            maps = []
            for i in range(count):
                start, end, f_off = struct.unpack("<QQQ", n["desc"][offset:offset+24])
                offset += 24
                maps.append((start, end, f_off))
            names = n["desc"][offset:].split(b"\x00")
            for i in range(min(count, len(names))):
                path = names[i].decode("utf-8", errors="ignore")
                if path:
                    print(f"  0x{maps[i][0]:016x} - 0x{maps[i][1]:016x} (offset 0x{maps[i][2]:x}) {path}")
            return
    print("Error: NT_FILE note not found", file=sys.stderr)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: coredump-analyzer <info|registers|siginfo|maps> <core-file>")
        sys.exit(1)

    cmd = sys.argv[1]
    core_path = sys.argv[2]
    result = parse_core(core_path)

    if cmd == "info":
        print_info(result)
    elif cmd == "registers":
        print_registers(result)
    elif cmd == "siginfo":
        print_siginfo(result)
    elif cmd == "maps":
        print_maps(result)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
EOF
chmod +x "$TARGET_DIR/bin/coredump-analyzer"

# 6. Create bin/elf-inspector (Extracts Build ID and ELF sections)
cat << 'EOF' > "$TARGET_DIR/bin/elf-inspector"
#!/usr/bin/env python3
import sys
import os
import struct

def inspect_elf(filepath):
    if not os.path.exists(filepath):
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    with open(filepath, "rb") as f:
        data = f.read()

    if len(data) < 64 or data[0:4] != b"\x7fELF":
        print("Error: invalid ELF binary", file=sys.stderr)
        sys.exit(1)

    e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, e_ehsize, e_phentsize, e_phnum = struct.unpack("<HHIQQQIHHH", data[16:58])
    
    build_id = None
    for i in range(e_phnum):
        off = e_phoff + (i * e_phentsize)
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack("<IIQQQQQQ", data[off:off+56])
        if p_type == 4: # PT_NOTE
            note_data = data[p_offset:p_offset+p_filesz]
            n_off = 0
            while n_off + 12 <= len(note_data):
                n_namesz, n_descsz, n_type = struct.unpack("<III", note_data[n_off:n_off+12])
                n_off += 12
                name_padded = (n_namesz + 3) & ~3
                desc_padded = (n_descsz + 3) & ~3
                name = note_data[n_off:n_off+n_namesz].rstrip(b"\x00").decode("utf-8", errors="ignore")
                n_off += name_padded
                desc = note_data[n_off:n_off+n_descsz]
                n_off += desc_padded
                if name == "GNU" and n_type == 3: # NT_GNU_BUILD_ID
                    build_id = desc.hex()

    print(f"ELF Type: {'ET_DYN (Position-Independent Executable)' if e_type == 3 else 'ET_EXEC'}")
    print(f"Machine: {'x86_64' if e_machine == 62 else str(e_machine)}")
    print(f"Entry Point: 0x{e_entry:x}")
    if build_id:
        print(f"GNU Build ID: {build_id}")
    else:
        print("GNU Build ID: None")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: elf-inspector <elf-file>")
        sys.exit(1)
    inspect_elf(sys.argv[1])
EOF
chmod +x "$TARGET_DIR/bin/elf-inspector"

# 7. Create bin/verify-worker (Execution harness)
cat << 'EOF' > "$TARGET_DIR/bin/verify-worker"
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME:-/root}/segfault-incident"
CONF="$TARGET_DIR/config/worker.env"

if [ ! -f "$CONF" ]; then
    echo "Error: configuration file $CONF missing!"
    exit 1
fi

TELEMETRY_ENABLED="false"
TELEMETRY_ENDPOINT=""

while IFS='=' read -r key val || [ -n "$key" ]; do
    key=$(echo "$key" | tr -d ' ' || true)
    val=$(echo "$val" | tr -d ' "' || true)
    case "$key" in
        TELEMETRY_ENABLED) TELEMETRY_ENABLED="$val" ;;
        TELEMETRY_ENDPOINT) TELEMETRY_ENDPOINT="$val" ;;
    esac
done < "$CONF"

echo "=== Verifying Batch Worker Execution ==="
echo "Configuration: TELEMETRY_ENABLED=$TELEMETRY_ENABLED, TELEMETRY_ENDPOINT=$TELEMETRY_ENDPOINT"

if [ "$TELEMETRY_ENABLED" = "true" ] && [ -z "$TELEMETRY_ENDPOINT" ]; then
    echo "[worker_service] Initializing batch processor with 100 records..."
    echo "[worker_service] Processing batch record 1..."
    echo "[kernel] worker_service[12480]: segfault at 0 ip 000055d7a81211e4 sp 00007ffc6422b310 error 4 in worker_service[55d7a8121000+1000]"
    echo "Segmentation fault (core dumped)"
    exit 139
fi

echo "[worker_service] Initializing batch processor with 100 records..."
for i in $(seq 1 100); do
    if [ "$TELEMETRY_ENABLED" = "true" ]; then
        echo "  [record $i] processed, dispatched telemetry to $TELEMETRY_ENDPOINT" > /dev/null
    else
        echo "  [record $i] processed (telemetry disabled)" > /dev/null
    fi
done

echo "=== Verification SUCCESS ==="
echo "100/100 records processed successfully with 0 errors and 0 segfaults."
exit 0
EOF
chmod +x "$TARGET_DIR/bin/verify-worker"
