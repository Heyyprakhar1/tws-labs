#!/bin/bash
set -euo pipefail

BASE="${LAB_HOME:-$HOME}"
[ -n "$BASE" ] && [ -d "$BASE" ] || { echo "Fatal: HOME not set." >&2; exit 1; }

INCIDENT="${SSH_INCIDENT_DIR:-$BASE/ssh-incident}"
rm -rf "$INCIDENT"
mkdir -p "$INCIDENT"/{bin,lib,client/.ssh,server/home/app-operator/.ssh,server/var/log,server/etc/ssh,reports}

# ─── 1. Provision lib/ssh-crypto.js (Core OpenSSL Cryptographic Verification Engine) ───
cat << 'CRYPTO_EOF' > "$INCIDENT/lib/ssh-crypto.js"
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

function derivePublicPem(privKeyPath) {
  return execFileSync('openssl', ['pkey', '-in', privKeyPath, '-pubout'], {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function encodeMpint(buf) {
  if (buf.length === 0) return Buffer.alloc(4);
  if (buf[0] & 0x80) {
    const b = Buffer.alloc(buf.length + 1);
    b[0] = 0;
    buf.copy(b, 1);
    buf = b;
  }
  const len = Buffer.alloc(4);
  len.writeUInt32BE(buf.length);
  return Buffer.concat([len, buf]);
}

function encodeString(str) {
  const buf = Buffer.from(str, 'utf8');
  const len = Buffer.alloc(4);
  len.writeUInt32BE(buf.length);
  return Buffer.concat([len, buf]);
}

function pemToOpenSsh(pubPem, comment = 'app-operator@internal-srv') {
  const pubKey = crypto.createPublicKey(pubPem);
  const jwk = pubKey.export({ format: 'jwk' });
  if (jwk.kty !== 'RSA') throw new Error(`Unsupported key type: ${jwk.kty}`);
  const eBuf = Buffer.from(jwk.e, 'base64url');
  const nBuf = Buffer.from(jwk.n, 'base64url');
  const blob = Buffer.concat([
    encodeString('ssh-rsa'),
    encodeMpint(eBuf),
    encodeMpint(nBuf),
  ]);
  return `ssh-rsa ${blob.toString('base64')} ${comment}`;
}

function openSshToPem(line) {
  const parts = line.trim().split(/\s+/);
  if (parts.length < 2 || parts[0] !== 'ssh-rsa') return null;
  try {
    const raw = Buffer.from(parts[1], 'base64');
    let offset = 0;
    function readString() {
      if (offset + 4 > raw.length) return null;
      const len = raw.readUInt32BE(offset);
      offset += 4;
      if (offset + len > raw.length) return null;
      const s = raw.subarray(offset, offset + len);
      offset += len;
      return s;
    }
    const type = readString();
    if (!type || type.toString('utf8') !== 'ssh-rsa') return null;
    const e = readString();
    let n = readString();
    if (!e || !n) return null;
    if (n[0] === 0) n = n.subarray(1);
    const pub = crypto.createPublicKey({
      key: { kty: 'RSA', e: e.toString('base64url'), n: n.toString('base64url') },
      format: 'jwk',
    });
    return pub.export({ type: 'spki', format: 'pem' });
  } catch {
    return null;
  }
}

function parseAuthorizedKeys(content) {
  const keys = [];
  const pemMatches = content.match(/-----BEGIN PUBLIC KEY-----[\s\S]*?-----END PUBLIC KEY-----/g);
  if (pemMatches) {
    for (const pem of pemMatches) {
      try {
        crypto.createPublicKey(pem);
        keys.push({ format: 'pem', pem: pem.trim(), raw: pem });
      } catch {}
    }
  }
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('ssh-rsa ')) {
      const pem = openSshToPem(trimmed);
      if (pem) {
        keys.push({ format: 'openssh', pem: pem.trim(), raw: trimmed });
      }
    }
  }
  return keys;
}

function getFingerprint(pubPem, comment = 'app-operator@internal-srv') {
  const pub = crypto.createPublicKey(pubPem);
  const jwk = pub.export({ format: 'jwk' });
  const eBuf = Buffer.from(jwk.e, 'base64url');
  const nBuf = Buffer.from(jwk.n, 'base64url');
  const blob = Buffer.concat([
    encodeString('ssh-rsa'),
    encodeMpint(eBuf),
    encodeMpint(nBuf),
  ]);
  const hash = crypto.createHash('sha256').update(blob).digest('base64').replace(/=+$/, '');
  return `2048 SHA256:${hash} ${comment} (RSA)`;
}

function verifyKeyAgreement(privKeyPath, authorizedKeysContent) {
  if (!fs.existsSync(privKeyPath)) {
    return { verified: false, keyCount: 0, error: 'Private key file does not exist' };
  }

  const keys = parseAuthorizedKeys(authorizedKeysContent);
  if (keys.length === 0) {
    return { verified: false, keyCount: 0, error: 'No valid public keys found in authorized_keys' };
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ssh-openssl-'));
  const noncePath = path.join(tmpDir, 'nonce.bin');
  const sigPath = path.join(tmpDir, 'sig.bin');
  const pubPath = path.join(tmpDir, 'pub.pem');

  try {
    const nonce = crypto.randomBytes(32);
    fs.writeFileSync(noncePath, nonce);

    // Sign challenge nonce using OpenSSL CLI
    execFileSync('openssl', [
      'dgst', '-sha256', '-sign', privKeyPath,
      '-out', sigPath, noncePath
    ], { stdio: ['pipe', 'pipe', 'pipe'] });

    // Verify against each parsed candidate public key using OpenSSL CLI
    for (const k of keys) {
      fs.writeFileSync(pubPath, k.pem);
      try {
        const out = execFileSync('openssl', [
          'dgst', '-sha256', '-verify', pubPath,
          '-signature', sigPath, noncePath
        ], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });

        if (out.includes('Verified OK')) {
          return { verified: true, keyCount: keys.length, matchingKey: k };
        }
      } catch {
        // OpenSSL verification failed for this candidate
      }
    }

    return { verified: false, keyCount: keys.length, error: 'Cryptographic signature verification failed for all keys' };
  } catch (err) {
    return { verified: false, keyCount: keys.length, error: `OpenSSL signature execution error: ${err.message}` };
  } finally {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  }
}

module.exports = {
  derivePublicPem,
  pemToOpenSsh,
  openSshToPem,
  parseAuthorizedKeys,
  getFingerprint,
  verifyKeyAgreement,
};
CRYPTO_EOF
chmod 0644 "$INCIDENT/lib/ssh-crypto.js"

# ─── 2. Provision bin/ssh-keygen ───
cat << 'KEYGEN_EOF' > "$INCIDENT/bin/ssh-keygen"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { derivePublicPem, pemToOpenSsh, getFingerprint } = require('../lib/ssh-crypto');

const args = process.argv.slice(2);
let keyPath = null;
let exportPub = false;
let fingerprint = false;
let comment = 'app-operator@internal-srv';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '-y') exportPub = true;
  else if (args[i] === '-l') fingerprint = true;
  else if (args[i] === '-f' && i + 1 < args.length) keyPath = args[++i];
  else if (args[i] === '-c' && i + 1 < args.length) comment = args[++i];
  else if (args[i] === '-h' || args[i] === '--help') {
    console.log('Usage: ssh-keygen [-y -f <private_key>] [-l -f <key_file>] [-c <comment>]');
    process.exit(0);
  }
}

if (!keyPath) {
  console.error('ssh-keygen: option requires an argument -- f');
  console.error('Usage: ssh-keygen [-y -f <private_key>] [-l -f <key_file>] [-c <comment>]');
  process.exit(1);
}

if (!fs.existsSync(keyPath)) {
  console.error(`ssh-keygen: ${keyPath}: No such file or directory`);
  process.exit(1);
}

if (exportPub) {
  try {
    // OpenSSL public-key derivation: openssl pkey -in <privkey> -pubout
    const pubPem = derivePublicPem(keyPath);
    console.log(pemToOpenSsh(pubPem, comment));
  } catch (e) {
    console.error(`ssh-keygen: load failed via openssl: ${e.message}`);
    process.exit(1);
  }
} else if (fingerprint) {
  try {
    const content = fs.readFileSync(keyPath, 'utf8');
    let pubPem;
    if (content.includes('BEGIN PRIVATE KEY') || content.includes('BEGIN RSA PRIVATE KEY')) {
      pubPem = derivePublicPem(keyPath);
    } else {
      pubPem = content;
    }
    console.log(getFingerprint(pubPem, comment));
  } catch (e) {
    console.error(`ssh-keygen: cannot get fingerprint: ${e.message}`);
    process.exit(1);
  }
} else {
  console.log('Usage: ssh-keygen [-y -f <private_key>] [-l -f <key_file>] [-c <comment>]');
}
KEYGEN_EOF
chmod 0755 "$INCIDENT/bin/ssh-keygen"

# ─── 3. Provision bin/ssh-connect ───
cat << 'CONNECT_EOF' > "$INCIDENT/bin/ssh-connect"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { verifyKeyAgreement } = require('../lib/ssh-crypto');

const baseDir = process.env.SSH_INCIDENT_DIR || path.resolve(__dirname, '..');
const clientKeyPath = path.resolve(baseDir, 'client/.ssh/id_rsa');
const serverHome = path.resolve(baseDir, 'server/home/app-operator');
const serverSshDir = path.resolve(serverHome, '.ssh');
const authKeysPath = path.resolve(serverSshDir, 'authorized_keys');
const authLogPath = path.resolve(baseDir, 'server/var/log/auth.log');

function logAuth(message) {
  const now = new Date();
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const month = months[now.getMonth()];
  const day = String(now.getDate()).padStart(2, ' ');
  const time = now.toTimeString().split(' ')[0];
  const pid = process.pid;
  const line = `${month} ${day} ${time} internal-srv sshd[${pid}]: ${message}\n`;
  try {
    fs.appendFileSync(authLogPath, line);
  } catch {}
}

// 1. Client-side private key validation
if (!fs.existsSync(clientKeyPath)) {
  console.error(`Warning: Identity file ${clientKeyPath} not accessible: No such file or directory.`);
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

const clientStat = fs.statSync(clientKeyPath);
const clientMode = clientStat.mode & 0o777;

// OpenSSH client rule: private key must not be accessible by group or others (mode & 0077 == 0)
if ((clientMode & 0o077) !== 0) {
  const octal = '0' + clientMode.toString(8);
  console.error('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');
  console.error('@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @');
  console.error('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@');
  console.error(`Permissions ${octal} for 'client/.ssh/id_rsa' are too open.`);
  console.error('It is required that your private key files are NOT accessible by others.');
  console.error('This private key will be ignored.');
  console.error('Load key "client/.ssh/id_rsa": bad permissions');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

// 2. Server-side StrictModes validation
const currentUid = process.getuid ? process.getuid() : clientStat.uid;

if (!fs.existsSync(serverHome)) {
  logAuth('Authentication refused: home directory does not exist');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
const homeStat = fs.statSync(serverHome);
if ((homeStat.mode & 0o022) !== 0) {
  logAuth('Authentication refused: bad ownership or modes for directory /home/app-operator');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
if (homeStat.uid !== currentUid && homeStat.uid !== 0) {
  logAuth('Authentication refused: bad ownership or modes for directory /home/app-operator');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

if (!fs.existsSync(serverSshDir)) {
  logAuth('Authentication refused: .ssh directory does not exist');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
const sshDirStat = fs.statSync(serverSshDir);
if ((sshDirStat.mode & 0o022) !== 0) {
  logAuth('Authentication refused: bad ownership or modes for directory /home/app-operator/.ssh');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
if (sshDirStat.uid !== currentUid && sshDirStat.uid !== 0) {
  logAuth('Authentication refused: bad ownership or modes for directory /home/app-operator/.ssh');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

if (!fs.existsSync(authKeysPath)) {
  logAuth('Authentication refused: authorized_keys does not exist');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
const authKeysStat = fs.statSync(authKeysPath);
if ((authKeysStat.mode & 0o022) !== 0) {
  logAuth('Authentication refused: bad ownership or modes for file /home/app-operator/.ssh/authorized_keys');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}
if (authKeysStat.uid !== currentUid && authKeysStat.uid !== 0) {
  logAuth('Authentication refused: bad ownership or modes for file /home/app-operator/.ssh/authorized_keys');
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

// 3. Cryptographic authentication using OpenSSL CLI
const authKeysContent = fs.readFileSync(authKeysPath, 'utf8');
const verifyResult = verifyKeyAgreement(clientKeyPath, authKeysContent);

if (!verifyResult.verified) {
  logAuth(`Failed publickey for app-operator from 10.0.4.12 port 54322 ssh2: RSA (${verifyResult.error || 'key mismatch'})`);
  logAuth('Connection closed by authenticating user app-operator 10.0.4.12 port 54322 [preauth]');
  console.error('app-operator@internal-srv: Permission denied (publickey).');
  process.exit(255);
}

// Authentication SUCCESS!
logAuth('Accepted publickey for app-operator from 10.0.4.12 port 54322 ssh2: RSA');
console.log('Authenticated to internal-srv ([10.0.4.10]:22) using "client/.ssh/id_rsa".');
console.log('Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.8.0-generic x86_64)');
console.log('');
console.log(' * Documentation:  https://help.ubuntu.com');
console.log(' * Management:     https://landscape.canonical.com');
console.log(' * Support:        https://ubuntu.com/pro');
console.log('');
console.log('System information as of Fri Nov  7 20:45:20 UTC 2026');
console.log('');
console.log('  System load:  0.08               Processes:             102');
console.log('  Usage of /:   18.2% of 28.50GB   Users logged in:       1');
console.log('  Memory usage: 22%                IPv4 address for eth0: 10.0.4.10');
console.log('');
console.log('Last login: Fri Nov  7 18:22:10 2026 from 10.0.4.12');
console.log('app-operator@internal-srv:~$ ');
console.log('Connection to internal-srv closed.');
process.exit(0);
CONNECT_EOF
chmod 0755 "$INCIDENT/bin/ssh-connect"

# ─── 4. Provision bin/verify-ssh ───
cat << 'VERIFY_EOF' > "$INCIDENT/bin/verify-ssh"
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { verifyKeyAgreement } = require('../lib/ssh-crypto');

const baseDir = process.env.SSH_INCIDENT_DIR || path.resolve(__dirname, '..');
const clientKeyPath = path.resolve(baseDir, 'client/.ssh/id_rsa');
const serverHome = path.resolve(baseDir, 'server/home/app-operator');
const serverSshDir = path.resolve(serverHome, '.ssh');
const authKeysPath = path.resolve(serverSshDir, 'authorized_keys');
const markerPath = path.resolve(baseDir, '.ssh-validated');

console.log('=== SSH Access & Hardening Audit ===');
let allPassed = true;

// 1. Client private key permissions
if (!fs.existsSync(clientKeyPath)) {
  console.log('[FAIL] Client private key: client/.ssh/id_rsa does not exist.');
  allPassed = false;
} else {
  const cStat = fs.statSync(clientKeyPath);
  const cMode = cStat.mode & 0o777;
  const oct = '0' + cMode.toString(8);
  if ((cMode & 0o077) !== 0) {
    console.log(`[FAIL] Client private key: permissions ${oct} are too open.`);
    console.log('       Private keys must NOT be accessible by group or others (use 0600 or 0400).');
    allPassed = false;
  } else {
    console.log(`[OK]   Client private key permissions: mode ${oct} (not accessible by group/others)`);
  }
}

// 2. Server StrictModes
const currentUid = process.getuid ? process.getuid() : 1000;

function checkStrict(itemPath, label, isDir) {
  if (!fs.existsSync(itemPath)) {
    console.log(`[FAIL] Server StrictModes: ${label} does not exist.`);
    allPassed = false;
    return;
  }
  const st = fs.statSync(itemPath);
  const mode = st.mode & 0o777;
  const oct = '0' + mode.toString(8);
  if ((mode & 0o022) !== 0) {
    console.log(`[FAIL] Server StrictModes: ${label} has mode ${oct} (writable by group/others).`);
    console.log('       StrictModes requires that group and others cannot write to this path.');
    allPassed = false;
  } else if (st.uid !== currentUid && st.uid !== 0) {
    console.log(`[FAIL] Server StrictModes: ${label} is owned by UID ${st.uid} (must be session user or root).`);
    allPassed = false;
  } else {
    console.log(`[OK]   Server StrictModes: ${label} mode ${oct}, owner UID ${st.uid}`);
  }
}

checkStrict(serverHome, 'server/home/app-operator', true);
checkStrict(serverSshDir, 'server/home/app-operator/.ssh', true);
checkStrict(authKeysPath, 'server/home/app-operator/.ssh/authorized_keys', false);

// 3. Cryptographic Key Agreement using OpenSSL CLI
let keyMatch = false;
if (fs.existsSync(clientKeyPath) && fs.existsSync(authKeysPath)) {
  const authKeysContent = fs.readFileSync(authKeysPath, 'utf8');
  const verifyResult = verifyKeyAgreement(clientKeyPath, authKeysContent);

  if (verifyResult.verified) {
    keyMatch = true;
    console.log('[OK]   Cryptographic Key Agreement: OpenSSL signature verification PASSED');
  } else {
    console.log(`[FAIL] Cryptographic Key Agreement: OpenSSL signature verification FAILED (${verifyResult.error})`);
    console.log('       Derive matching public key from client/.ssh/id_rsa using ./bin/ssh-keygen or openssl.');
    allPassed = false;
  }
} else {
  allPassed = false;
}

// 4. Summary & Marker
if (allPassed) {
  const marker = [
    'VALIDATED=true',
    `VALIDATED_AT=${new Date().toISOString()}`,
    `SESSION_USER=app-operator`,
    `TARGET_HOST=internal-srv`,
    `STRICTMODES=PASS`,
    `CLIENT_KEY=PASS`,
    `KEY_MATCH=PASS`,
    `OPENSSL_VERIFIED=PASS`,
    `AUTH_RESULT=SUCCESS`,
  ].join('\n') + '\n';
  fs.writeFileSync(markerPath, marker, { mode: 0o600 });
  console.log('\nRESULT: ALL CHECKS PASSED. SSH authentication hardened and operational.');
  process.exit(0);
} else {
  try { fs.unlinkSync(markerPath); } catch {}
  console.log('\nRESULT: VERIFICATION FAILED. Correct the highlighted issues and rerun ./bin/verify-ssh.');
  process.exit(1);
}
VERIFY_EOF
chmod 0755 "$INCIDENT/bin/verify-ssh"

# ─── 5. Generate client private key (2048-bit RSA) with unsafe permissions (0644) ───
openssl genrsa -out "$INCIDENT/client/.ssh/id_rsa" 2048 2>/dev/null
chmod 0644 "$INCIDENT/client/.ssh/id_rsa"

# ─── 6. Generate stale/mismatched key and populate authorized_keys with unsafe permissions (0666) ───
STALE_KEY="$INCIDENT/.stale_key.tmp"
openssl genrsa -out "$STALE_KEY" 2048 2>/dev/null
"$INCIDENT/bin/ssh-keygen" -y -f "$STALE_KEY" -c "legacy-operator@internal-srv" > "$INCIDENT/server/home/app-operator/.ssh/authorized_keys"
rm -f "$STALE_KEY"
chmod 0666 "$INCIDENT/server/home/app-operator/.ssh/authorized_keys"

# ─── 7. Set unsafe permissions on server home and .ssh directories (0777) ───
chmod 0777 "$INCIDENT/server/home/app-operator"
chmod 0777 "$INCIDENT/server/home/app-operator/.ssh"

# ─── 8. Provision server sshd_config ───
cat << 'SSHD_EOF' > "$INCIDENT/server/etc/ssh/sshd_config"
# Simulated OpenSSH Server Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin no
StrictModes yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
SSHD_EOF
chmod 0644 "$INCIDENT/server/etc/ssh/sshd_config"

# ─── 9. Populate realistic server authentication log ───
cat << 'LOG_EOF' > "$INCIDENT/server/var/log/auth.log"
Nov 07 18:05:01 internal-srv sshd[1041]: Server listening on 0.0.4.10 port 22.
Nov 07 18:10:14 internal-srv sshd[1042]: Connection from 10.0.4.12 port 54320 on 10.0.4.10 port 22
Nov 07 18:10:14 internal-srv sshd[1042]: Authentication refused: bad ownership or modes for directory /home/app-operator
Nov 07 18:10:14 internal-srv sshd[1042]: Connection closed by authenticating user app-operator 10.0.4.12 port 54320 [preauth]
Nov 07 18:15:22 internal-srv sshd[1045]: Connection from 10.0.4.12 port 54321 on 10.0.4.10 port 22
Nov 07 18:15:22 internal-srv sshd[1045]: Authentication refused: bad ownership or modes for directory /home/app-operator
Nov 07 18:15:22 internal-srv sshd[1045]: Connection closed by authenticating user app-operator 10.0.4.12 port 54321 [preauth]
LOG_EOF
chmod 0644 "$INCIDENT/server/var/log/auth.log"

# Clear any previous validation receipt
rm -f "$INCIDENT/.ssh-validated"
