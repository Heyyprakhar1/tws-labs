const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'intermediate', 'ssh-authentication-troubleshooting');
const STEPS = ['diagnose-auth-failure', 'repair-server-permissions', 'repair-client-key', 'validate-ssh-access'];

function runScript(cwd, scriptPath, env = {}) {
  return spawnSync('bash', [scriptPath], {
    cwd,
    env: {
      ...process.env,
      HOME: cwd,
      LAB_HOME: cwd,
      LAB_LIB: path.join(__dirname, '..', '..', 'labs', 'lib.sh'),
      ...env,
    },
    timeout: 15000,
    encoding: 'utf8',
  });
}

function cleanupDir(dir) {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-108 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'ssh-authentication-troubleshooting');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-108');
  assert.equal(challenge.level, 'intermediate');
  assert.equal(challenge.tasksCount, 4);
  assert.equal(challenge.domain, 'linux');
});

test('LNX-CH-108: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-flow-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup must exit 0: ${setupRes.out}`);

    // All checks must fail initially
    for (const step of STEPS) {
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const before = runScript(tmpHome, checkPath);
      assert.notEqual(before.status, 0, `Check ${step} must fail before solution: ${before.stdout}`);
    }

    // Solutions and checks in sequence
    for (const step of STEPS) {
      const solPath = path.join(CH_DIR, 'solutions', `${step}.sh`);
      const solRes = runScript(tmpHome, solPath);
      assert.equal(solRes.status, 0, `Solution ${step} must exit 0: ${solRes.stderr}`);

      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const after = runScript(tmpHome, checkPath);
      assert.equal(after.status, 0, `Check ${step} must pass after solution: ${after.stdout}`);
    }

    // Verify simulated authentication succeeded
    const inc = path.join(tmpHome, 'ssh-incident');
    const connectRes = spawnSync(path.join(inc, 'bin', 'ssh-connect'), [], {
      cwd: inc,
      encoding: 'utf8',
    });
    assert.equal(connectRes.status, 0, `ssh-connect must exit 0: ${connectRes.stderr}`);
    assert.match(connectRes.stdout, /Authenticated to internal-srv/);

    // Verify validation marker exists and confirms OpenSSL verification
    const marker = path.join(inc, '.ssh-validated');
    assert.ok(fs.existsSync(marker), 'Validation marker must exist');
    const markerContent = fs.readFileSync(marker, 'utf8');
    assert.match(markerContent, /AUTH_RESULT=SUCCESS/);
    assert.match(markerContent, /OPENSSL_VERIFIED=PASS/);
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-108: each skip-ahead script is independently executable and idempotent', () => {
  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-108-skip-${step}-`));
    try {
      const skipPath = path.join(CH_DIR, 'setup', `${step}.sh`);
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);

      // First run: cold directory
      const firstRun = runScript(tmpHome, skipPath);
      assert.equal(firstRun.status, 0, `Skip-ahead ${step} first run must exit 0: ${firstRun.stderr}`);

      const checkFirst = runScript(tmpHome, checkPath);
      assert.equal(checkFirst.status, 0, `Check ${step} must pass after first skip-ahead: ${checkFirst.stdout}`);

      // Second run: idempotency test
      const secondRun = runScript(tmpHome, skipPath);
      assert.equal(secondRun.status, 0, `Skip-ahead ${step} second run must exit 0: ${secondRun.stderr}`);

      const checkSecond = runScript(tmpHome, checkPath);
      assert.equal(checkSecond.status, 0, `Check ${step} must pass after second skip-ahead: ${checkSecond.stdout}`);
    } finally {
      cleanupDir(tmpHome);
    }
  }
});

test('LNX-CH-108: server StrictModes permission validation and alternative valid modes', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-strictmodes-'));
  const inc = path.join(tmpHome, 'ssh-incident');
  const serverHome = path.join(inc, 'server', 'home', 'app-operator');
  const serverSsh = path.join(serverHome, '.ssh');
  const authKeys = path.join(serverSsh, 'authorized_keys');
  const checkPath = path.join(CH_DIR, 'checks', 'repair-server-permissions.sh');

  try {
    const setupScript = path.join(CH_DIR, 'setup.sh');
    runScript(tmpHome, setupScript);

    // Initial state: home 0777, .ssh 0777, auth_keys 0666 -> must fail
    const initialCheck = runScript(tmpHome, checkPath);
    assert.notEqual(initialCheck.status, 0, 'Initial server permissions must fail');

    // 1. Safe recommended permissions: 0750, 0700, 0600 -> must pass
    fs.chmodSync(serverHome, 0o750);
    fs.chmodSync(serverSsh, 0o700);
    fs.chmodSync(authKeys, 0o600);
    const pass1 = runScript(tmpHome, checkPath);
    assert.equal(pass1.status, 0, `Permissions 0750/0700/0600 must pass: ${pass1.stdout}`);

    // 2. Safe alternative permissions: 0755, 0750, 0644 -> must pass (no group/world write)
    fs.chmodSync(serverHome, 0o755);
    fs.chmodSync(serverSsh, 0o750);
    fs.chmodSync(authKeys, 0o644);
    const pass2 = runScript(tmpHome, checkPath);
    assert.equal(pass2.status, 0, `Permissions 0755/0750/0644 must pass: ${pass2.stdout}`);

    // 3. Unsafe group-writable home: 0775 -> must fail
    fs.chmodSync(serverHome, 0o775);
    const failGroupHome = runScript(tmpHome, checkPath);
    assert.notEqual(failGroupHome.status, 0, 'Group-writable home (0775) must fail');
    assert.match(failGroupHome.stdout, /group or others have write permissions/);

    // Restore home
    fs.chmodSync(serverHome, 0o750);

    // 4. Unsafe group-writable .ssh: 0770 -> must fail
    fs.chmodSync(serverSsh, 0o770);
    const failGroupSsh = runScript(tmpHome, checkPath);
    assert.notEqual(failGroupSsh.status, 0, 'Group-writable .ssh (0770) must fail');

    // Restore .ssh
    fs.chmodSync(serverSsh, 0o700);

    // 5. Unsafe group-writable authorized_keys: 0664 -> must fail
    fs.chmodSync(authKeys, 0o664);
    const failGroupKeys = runScript(tmpHome, checkPath);
    assert.notEqual(failGroupKeys.status, 0, 'Group-writable authorized_keys (0664) must fail');

    // 6. Unsafe world-writable authorized_keys: 0666 -> must fail
    fs.chmodSync(authKeys, 0o666);
    const failWorldKeys = runScript(tmpHome, checkPath);
    assert.notEqual(failWorldKeys.status, 0, 'World-writable authorized_keys (0666) must fail');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-108: client private key permission validation', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-clientkey-'));
  const inc = path.join(tmpHome, 'ssh-incident');
  const clientKey = path.join(inc, 'client', '.ssh', 'id_rsa');
  const authKeys = path.join(inc, 'server', 'home', 'app-operator', '.ssh', 'authorized_keys');
  const checkPath = path.join(CH_DIR, 'checks', 'repair-client-key.sh');

  try {
    const setupScript = path.join(CH_DIR, 'setup.sh');
    runScript(tmpHome, setupScript);

    // Put matching public key in authorized_keys so we test key permissions specifically
    const keygenRes = spawnSync(path.join(inc, 'bin', 'ssh-keygen'), ['-y', '-f', clientKey], {
      cwd: inc,
      encoding: 'utf8',
    });
    assert.equal(keygenRes.status, 0);
    fs.writeFileSync(authKeys, keygenRes.stdout, { mode: 0o600 });

    // Initial key mode: 0644 -> must fail
    const fail644 = runScript(tmpHome, checkPath);
    assert.notEqual(fail644.status, 0, 'Client key mode 0644 must fail');
    assert.match(fail644.stdout, /must be 0600 or 0400/);

    // Key mode 0600 -> must pass
    fs.chmodSync(clientKey, 0o600);
    const pass600 = runScript(tmpHome, checkPath);
    assert.equal(pass600.status, 0, `Client key mode 0600 must pass: ${pass600.stdout}`);

    // Key mode 0400 (read-only by owner) -> must pass
    fs.chmodSync(clientKey, 0o400);
    const pass400 = runScript(tmpHome, checkPath);
    assert.equal(pass400.status, 0, `Client key mode 0400 must pass: ${pass400.stdout}`);

    // Key mode 0660 (group accessible) -> must fail
    fs.chmodSync(clientKey, 0o660);
    const fail660 = runScript(tmpHome, checkPath);
    assert.notEqual(fail660.status, 0, 'Client key mode 0660 must fail');

    // Key mode 0777 -> must fail
    fs.chmodSync(clientKey, 0o777);
    const fail777 = runScript(tmpHome, checkPath);
    assert.notEqual(fail777.status, 0, 'Client key mode 0777 must fail');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-108: OpenSSL cryptographic derivation, signature verification, and simulated auth path enforcement', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-openssl-'));
  const inc = path.join(tmpHome, 'ssh-incident');
  const clientKey = path.join(inc, 'client', '.ssh', 'id_rsa');
  const authKeys = path.join(inc, 'server', 'home', 'app-operator', '.ssh', 'authorized_keys');
  const checkPath = path.join(CH_DIR, 'checks', 'repair-client-key.sh');
  const sshConnect = path.join(inc, 'bin', 'ssh-connect');
  const setupScript = path.join(CH_DIR, 'setup.sh');

  try {
    runScript(tmpHome, setupScript);
    const cryptoLib = require(path.join(inc, 'lib', 'ssh-crypto.js'));

    // 1. Explicit proof: Public key is derived from client private key using OpenSSL
    const openSslDerivedPem = cryptoLib.derivePublicPem(clientKey);
    assert.ok(openSslDerivedPem.includes('BEGIN PUBLIC KEY'), 'OpenSSL derivePublicPem must yield SPKI PEM');

    // Confirm bin/ssh-keygen derives the matching key via OpenSSL
    const keygenRes = spawnSync(path.join(inc, 'bin', 'ssh-keygen'), ['-y', '-f', clientKey], {
      cwd: inc,
      encoding: 'utf8',
    });
    assert.equal(keygenRes.status, 0);
    const derivedOpenSsh = keygenRes.stdout.trim();
    assert.match(derivedOpenSsh, /^ssh-rsa AAAA/);

    // Parse the OpenSSH line to PEM and prove OpenSSL verification succeeds
    const convertedPem = cryptoLib.openSshToPem(derivedOpenSsh);
    assert.ok(convertedPem, 'OpenSSH key must convert to valid PEM for OpenSSL');

    // 2. Explicit proof: OpenSSL signature verification succeeds for matching authorized key
    const matchRes = cryptoLib.verifyKeyAgreement(clientKey, derivedOpenSsh);
    assert.equal(matchRes.verified, true, 'OpenSSL verifyKeyAgreement must succeed on matching key');

    // Also test direct OpenSSL CLI verification against derivedOpenSsh
    const testDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-openssl-cli-'));
    try {
      const noncePath = path.join(testDir, 'nonce.bin');
      const sigPath = path.join(testDir, 'sig.bin');
      const pubPath = path.join(testDir, 'pub.pem');
      fs.writeFileSync(noncePath, 'challenge-nonce-data');
      fs.writeFileSync(pubPath, convertedPem);

      execFileSync('openssl', ['dgst', '-sha256', '-sign', clientKey, '-out', sigPath, noncePath]);
      const cliVerify = execFileSync('openssl', [
        'dgst', '-sha256', '-verify', pubPath,
        '-signature', sigPath, noncePath,
      ], { encoding: 'utf8' });
      assert.match(cliVerify, /Verified OK/, 'Direct OpenSSL CLI verification must succeed');
    } finally {
      cleanupDir(testDir);
    }

    // 3. Explicit proof: OpenSSL verification fails for a different key
    const otherKeyPath = path.join(tmpHome, 'other_rsa');
    execFileSync('openssl', ['genrsa', '-out', otherKeyPath, '2048'], { stdio: 'ignore' });
    const otherPubPem = cryptoLib.derivePublicPem(otherKeyPath);
    const otherOpenSsh = cryptoLib.pemToOpenSsh(otherPubPem, 'other@srv');

    const mismatchRes = cryptoLib.verifyKeyAgreement(clientKey, otherOpenSsh);
    assert.equal(mismatchRes.verified, false, 'OpenSSL verifyKeyAgreement must fail on different key');
    assert.match(mismatchRes.error, /Cryptographic signature verification failed/);

    // 4. Explicit proof: Malformed and unsupported public keys are rejected
    assert.equal(cryptoLib.openSshToPem('ssh-rsa invalid-base64-content'), null);
    assert.equal(cryptoLib.openSshToPem('ssh-dss AAAAB3NzaC1kc3MA...'), null); // unsupported type
    assert.equal(cryptoLib.openSshToPem('arbitrary text garbage'), null);

    const malformedRes = cryptoLib.verifyKeyAgreement(clientKey, 'ssh-dss AAAAB3NzaC1kc3MA... fake@srv\n');
    assert.equal(malformedRes.verified, false);
    assert.match(malformedRes.error, /No valid public keys found/);

    // 5. Explicit proof: Simulated authentication path (ssh-connect) uses OpenSSL verification
    // Set safe permissions on client key and server directories
    fs.chmodSync(clientKey, 0o600);
    fs.chmodSync(path.join(inc, 'server', 'home', 'app-operator'), 0o750);
    fs.chmodSync(path.join(inc, 'server', 'home', 'app-operator', '.ssh'), 0o700);
    fs.chmodSync(authKeys, 0o600);

    // Case 5a: With mismatched key (having valid comment!), auth MUST fail
    fs.writeFileSync(authKeys, otherOpenSsh, { mode: 0o600 });
    const authFail = spawnSync(sshConnect, [], { cwd: inc, encoding: 'utf8' });
    assert.equal(authFail.status, 255, 'ssh-connect must exit 255 when OpenSSL verification fails');
    assert.match(authFail.stderr, /Permission denied \(publickey\)/);

    // Check auth.log records failure
    const authLog = fs.readFileSync(path.join(inc, 'server', 'var', 'log', 'auth.log'), 'utf8');
    assert.match(authLog, /Failed publickey for app-operator/);

    // Case 5b: With matching key, auth MUST succeed
    fs.writeFileSync(authKeys, derivedOpenSsh, { mode: 0o600 });
    const authPass = spawnSync(sshConnect, [], { cwd: inc, encoding: 'utf8' });
    assert.equal(authPass.status, 0, `ssh-connect must succeed with matching OpenSSL key: ${authPass.stderr}`);
    assert.match(authPass.stdout, /Authenticated to internal-srv/);

    // Case 5c: With PEM public key derived by openssl, auth MUST also succeed
    fs.writeFileSync(authKeys, openSslDerivedPem, { mode: 0o600 });
    const authPemPass = spawnSync(sshConnect, [], { cwd: inc, encoding: 'utf8' });
    assert.equal(authPemPass.status, 0, `ssh-connect must succeed with PEM public key: ${authPemPass.stderr}`);
    assert.match(authPemPass.stdout, /Authenticated to internal-srv/);

    // Case 5d: Check script repair-client-key.sh correctly passes
    const checkPass = runScript(tmpHome, checkPath);
    assert.equal(checkPass.status, 0, `Check repair-client-key must pass: ${checkPass.stdout}`);
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-108: concurrent sessions operate without cross-contamination', () => {
  const session1 = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-s1-'));
  const session2 = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-s2-'));

  try {
    const setupScript = path.join(CH_DIR, 'setup.sh');

    // Run setup for session 1
    const s1Res = runScript(session1, setupScript);
    assert.equal(s1Res.status, 0);

    // Run setup for session 2
    const s2Res = runScript(session2, setupScript);
    assert.equal(s2Res.status, 0);

    // Fix session 1 only
    for (const step of STEPS) {
      const solPath = path.join(CH_DIR, 'solutions', `${step}.sh`);
      runScript(session1, solPath);
    }

    // Verify session 1 passes all checks
    for (const step of STEPS) {
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const s1Check = runScript(session1, checkPath);
      assert.equal(s1Check.status, 0, `Session 1 check ${step} must pass`);
    }

    // Verify session 2 still fails all checks (no leak from session 1)
    for (const step of STEPS) {
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const s2Check = runScript(session2, checkPath);
      assert.notEqual(s2Check.status, 0, `Session 2 check ${step} must still fail`);
    }
  } finally {
    cleanupDir(session1);
    cleanupDir(session2);
  }
});

test('LNX-CH-108: strict isolation - host SSH configuration is never accessed or modified', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-108-iso-'));
  try {
    const setupScript = path.join(CH_DIR, 'setup.sh');
    runScript(tmpHome, setupScript);

    // Verify everything is inside ssh-incident
    const inc = path.join(tmpHome, 'ssh-incident');
    assert.ok(fs.existsSync(inc), 'Incident directory must exist');

    // Run all solutions
    for (const step of STEPS) {
      const solPath = path.join(CH_DIR, 'solutions', `${step}.sh`);
      runScript(tmpHome, solPath);
    }

    // Verify no host files created in tmpHome outside ssh-incident
    const entries = fs.readdirSync(tmpHome);
    assert.deepEqual(entries, ['ssh-incident']);
  } finally {
    cleanupDir(tmpHome);
  }
});
