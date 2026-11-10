const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'intermediate', 'dns-resolution-troubleshooting');
const STEPS = ['diagnose-resolution', 'repair-hosts-entry', 'verify-resolver-config', 'validate-resolution'];

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
    timeout: 10000,
    encoding: 'utf8',
  });
}

function cleanupDir(home) {
  try {
    fs.rmSync(home, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-107 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'dns-resolution-troubleshooting');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-107');
  assert.equal(challenge.level, 'intermediate');
  assert.equal(challenge.tasksCount, 4);
});

test('LNX-CH-107: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-flow-'));

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
      assert.equal(solRes.status, 0, `Solution ${step} must exit 0: ${solRes.stderr || solRes.stdout}`);

      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const after = runScript(tmpHome, checkPath);
      assert.equal(after.status, 0, `Check ${step} must pass after solution: ${after.stderr || after.stdout}`);
    }
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (let i = 0; i < STEPS.length; i++) {
    const targetStep = STEPS[i];
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-107-skip-${i}-`));

    try {
      const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      assert.equal(setupRes.code, 0, `Setup for skip ${targetStep} must exit 0`);

      const skipScript = path.join(CH_DIR, 'setup', `${targetStep}.sh`);

      // First execution
      const skipRes = runScript(tmpHome, skipScript);
      assert.equal(skipRes.status, 0, `Skip-ahead ${targetStep} must exit 0: ${skipRes.stderr || skipRes.stdout}`);

      // Idempotency: second execution
      const skipRes2 = runScript(tmpHome, skipScript);
      assert.equal(skipRes2.status, 0, `Skip-ahead ${targetStep} must be idempotent`);

      // All prior steps must pass
      for (let j = 0; j < i; j++) {
        const priorCheck = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[j]}.sh`));
        assert.equal(priorCheck.status, 0, `Prior step ${STEPS[j]} must pass after skipping to ${targetStep}`);
      }

      // Target step must fail before solution
      const targetBefore = runScript(tmpHome, path.join(CH_DIR, 'checks', `${targetStep}.sh`));
      assert.notEqual(targetBefore.status, 0, `Target ${targetStep} must fail before solution`);

      // Target solution
      const solRes = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${targetStep}.sh`));
      assert.equal(solRes.status, 0, `Solution for ${targetStep} must exit 0`);

      // Target check must now pass
      const targetAfter = runScript(tmpHome, path.join(CH_DIR, 'checks', `${targetStep}.sh`));
      assert.equal(targetAfter.status, 0, `Target ${targetStep} must pass after solution`);
    } finally {
      cleanupDir(tmpHome);
    }
  }
});

test('LNX-CH-107: poisoned hosts entry takes precedence over DNS with files dns order', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-poison-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');

    // Normal application-style resolution returns poisoned 192.0.2.1
    const res = spawnSync('bash', [resolveBin, 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /192\.0\.2\.1/);
    assert.match(res.stdout, /source:\s*files/);

    // Source inspection flag
    const resSrc = spawnSync('bash', [resolveBin, '--source', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(resSrc.status, 0);
    assert.equal(resSrc.stdout.trim(), 'files');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: direct DNS queries bypass hosts file and return mock records', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-directdns-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const digBin = path.join(tmpHome, 'dns-incident', 'bin', 'dig-dns');

    // Direct DNS query against db.internal.corp returns legitimate 10.0.2.15 despite poisoned hosts
    const res = spawnSync('bash', [digBin, 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /10\.0\.2\.15/);
    assert.equal(res.stdout.includes('192.0.2.1'), false, 'Direct DNS must never return poisoned hosts IP');

    // Short mode
    const resShort = spawnSync('bash', [digBin, '+short', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(resShort.status, 0);
    assert.equal(resShort.stdout.trim(), '10.0.2.15');

    // Direct DNS for api.internal.corp
    const resApi = spawnSync('bash', [digBin, '+short', 'api.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(resApi.status, 0);
    assert.equal(resApi.stdout.trim(), '10.0.2.20');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: correcting hosts entry restores expected DNS resolution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-repairhosts-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');
    const hostsFile = path.join(tmpHome, 'dns-incident', 'etc', 'hosts');

    // Initially returns 192.0.2.1
    const before = spawnSync('bash', [resolveBin, '--ip', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(before.stdout.trim(), '192.0.2.1');

    // Remove poisoned entry
    const content = fs.readFileSync(hostsFile, 'utf8');
    fs.writeFileSync(hostsFile, content.replace(/.*192\.0\.2\.1.*\n/, ''));

    // Now returns 10.0.2.15 from dns
    const after = spawnSync('bash', [resolveBin, 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(after.status, 0);
    assert.match(after.stdout, /10\.0\.2\.15/);
    assert.match(after.stdout, /source:\s*dns/);
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: incorrect nameserver configuration causes DNS failure', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-badns-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const digBin = path.join(tmpHome, 'dns-incident', 'bin', 'dig-dns');
    const resolvFile = path.join(tmpHome, 'dns-incident', 'etc', 'resolv.conf');

    // Change nameserver to unreachable IP
    fs.writeFileSync(resolvFile, 'nameserver 10.0.0.99\nsearch internal.corp\n');

    const res = spawnSync('bash', [digBin, 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.notEqual(res.status, 0, 'dig-dns must fail when nameserver is not 10.0.0.53');
    assert.match(res.stderr, /connection timed out/);
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: NSS order genuinely controls resolution behavior (dns files vs files dns)', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-nssorder-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');
    const nssFile = path.join(tmpHome, 'dns-incident', 'etc', 'nsswitch.conf');

    // With files dns: files takes precedence -> 192.0.2.1
    fs.writeFileSync(nssFile, 'hosts: files dns\n');
    const resFilesFirst = spawnSync('bash', [resolveBin, '--ip', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(resFilesFirst.stdout.trim(), '192.0.2.1');

    // With dns files: dns takes precedence -> 10.0.2.15
    fs.writeFileSync(nssFile, 'hosts: dns files\n');
    const resDnsFirst = spawnSync('bash', [resolveBin, '--ip', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(resDnsFirst.stdout.trim(), '10.0.2.15');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: search-domain resolution works for short hostnames and FQDN works', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-searchdomain-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');
    const resolvFile = path.join(tmpHome, 'dns-incident', 'etc', 'resolv.conf');
    const hostsFile = path.join(tmpHome, 'dns-incident', 'etc', 'hosts');

    // Remove poisoned entry from hosts so we test DNS search domain
    fs.writeFileSync(hostsFile, '127.0.0.1 localhost\n');

    // Initially resolv.conf has search dev.corp -> short name 'db' fails
    const failShort = spawnSync('bash', [resolveBin, 'db'], { cwd: tmpHome, encoding: 'utf8' });
    assert.notEqual(failShort.status, 0, 'Short hostname db must fail with search dev.corp');

    // FQDN db.internal.corp works regardless of search domain
    const fqdnRes = spawnSync('bash', [resolveBin, '--ip', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(fqdnRes.status, 0);
    assert.equal(fqdnRes.stdout.trim(), '10.0.2.15');

    // Update search domain to internal.corp
    fs.writeFileSync(resolvFile, 'nameserver 10.0.0.53\nsearch internal.corp\n');

    // Now short name 'db' succeeds and returns 10.0.2.15
    const successShort = spawnSync('bash', [resolveBin, '--ip', 'db'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(successShort.status, 0);
    assert.equal(successShort.stdout.trim(), '10.0.2.15');

    // Short name 'api' also succeeds
    const successApi = spawnSync('bash', [resolveBin, '--ip', 'api'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(successApi.status, 0);
    assert.equal(successApi.stdout.trim(), '10.0.2.20');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: localhost resolves to 127.0.0.1 via files', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-localhost-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');
    const digBin = path.join(tmpHome, 'dns-incident', 'bin', 'dig-dns');

    // resolve-host localhost returns 127.0.0.1 (source: files)
    const res = spawnSync('bash', [resolveBin, 'localhost'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /127\.0\.0\.1/);
    assert.match(res.stdout, /source:\s*files/);

    // dig-dns localhost fails because localhost is not a DNS zone record
    const digRes = spawnSync('bash', [digBin, 'localhost'], { cwd: tmpHome, encoding: 'utf8' });
    assert.notEqual(digRes.status, 0, 'Direct DNS should not resolve localhost');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: repeated setup and cleanup are safe and idempotent', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-idempotent-'));

  try {
    // Run setup twice
    const res1 = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(res1.code, 0);

    const res2 = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(res2.code, 0);

    // Verify initial state is consistent
    const resolveBin = path.join(tmpHome, 'dns-incident', 'bin', 'resolve-host');
    const res = spawnSync('bash', [resolveBin, '--ip', 'db.internal.corp'], { cwd: tmpHome, encoding: 'utf8' });
    assert.equal(res.stdout.trim(), '192.0.2.1');
  } finally {
    cleanupDir(tmpHome);
  }
});

test('LNX-CH-107: two concurrent sessions remain isolated without cross-talk', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-conc-A-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-107-conc-B-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, homeA, undefined, {}, { isolateOutput: true });
    sandbox.runChallengeSetup(CH_DIR, homeB, undefined, {}, { isolateOutput: true });

    // Solve Session A completely
    for (const step of STEPS) {
      const solRes = runScript(homeA, path.join(CH_DIR, 'solutions', `${step}.sh`));
      assert.equal(solRes.status, 0);
      const chkRes = runScript(homeA, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.equal(chkRes.status, 0, `Session A check ${step} failed`);
    }

    // Session B must still be in initial state (all checks failing)
    for (const step of STEPS) {
      const chkResB = runScript(homeB, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(chkResB.status, 0, `Session B check ${step} should still fail`);
    }

    // Session A resolves db to 10.0.2.15
    const resA = spawnSync('bash', [path.join(homeA, 'dns-incident', 'bin', 'resolve-host'), '--ip', 'db.internal.corp'], { cwd: homeA, encoding: 'utf8' });
    assert.equal(resA.stdout.trim(), '10.0.2.15');

    // Session B still resolves db to 192.0.2.1
    const resB = spawnSync('bash', [path.join(homeB, 'dns-incident', 'bin', 'resolve-host'), '--ip', 'db.internal.corp'], { cwd: homeB, encoding: 'utf8' });
    assert.equal(resB.stdout.trim(), '192.0.2.1');
  } finally {
    cleanupDir(homeA);
    cleanupDir(homeB);
  }
});
