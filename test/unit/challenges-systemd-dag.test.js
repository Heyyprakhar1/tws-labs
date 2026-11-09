const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');
const { CHALLENGE_SKILLS } = require('../../src/challenge-pages');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'systemd-dependency-cycle');
const STEPS = [
  'diagnose-ordering-cycle',
  'investigate-ordering-dependencies',
  'remediate-ordering-cycle',
  'verify-topological-startup',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isPython = basename === 'systemd-analyze' || basename === 'systemctl';
  const isNode = scriptPath.endsWith('.js');
  const cmd = isNode ? 'node' : (isPython ? 'python3' : 'bash');
  return spawnSync(cmd, [scriptPath, ...args], {
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

test('LNX-CH-205 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'systemd-dependency-cycle');
  assert.ok(ch, 'systemd-dependency-cycle must be loadable');
  assert.equal(ch.id, 'LNX-CH-205');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'Systemd Unit Dependency Graphing & Ordering Cycle Triage');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-205: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['systemd-dependency-cycle'], 'Skills taxonomy must be registered for systemd-dependency-cycle');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['systemd-dependency-cycle']));
  assert.ok(CHALLENGE_SKILLS['systemd-dependency-cycle'].length >= 3);
});

test('LNX-CH-205: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-205-flow-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0, `setup.sh failed:\n${s.out}`);

    for (const step of STEPS) {
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const solPath = path.join(CH_DIR, 'solutions', `${step}.sh`);

      // Initial check must fail
      const pre = runScript(tmpHome, checkPath);
      assert.notEqual(pre.status, 0, `Check ${step} must fail before solution`);

      // Solution must succeed
      const sol = runScript(tmpHome, solPath);
      assert.equal(sol.status, 0, `Solution ${step} failed:\n${sol.stderr}\n${sol.stdout}`);

      // Post-solution check must pass
      const post = runScript(tmpHome, checkPath);
      assert.equal(post.status, 0, `Check ${step} must pass after solution:\n${post.stderr}\n${post.stdout}`);
    }
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-205: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-205-skip-${step}-`));
    try {
      const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      assert.equal(s.code, 0);

      const skipPath = path.join(CH_DIR, 'setup', `${step}.sh`);
      const res = runScript(tmpHome, skipPath);
      assert.equal(res.status, 0, `Skip-ahead ${step} failed:\n${res.stderr}\n${res.stdout}`);

      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const chk = runScript(tmpHome, checkPath);
      assert.equal(chk.status, 0, `Check ${step} must pass after skip-ahead:\n${chk.stderr}\n${chk.stdout}`);
    } finally {
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  }
});

test('LNX-CH-205: DAG cycle detection and cycle participant extraction', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-205-cycle-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const analyzeBin = path.join(tmpHome, 'systemd-incident', 'bin', 'systemd-analyze');
    const res = runScript(tmpHome, analyzeBin, ['verify']);
    assert.equal(res.status, 1, 'verify must fail when cycle exists');
    assert.match(res.stdout, /Found ordering cycle on payment-api\.service/);
    assert.match(res.stdout, /payment-api\.service/);
    assert.match(res.stdout, /payment-cache\.service/);
    assert.match(res.stdout, /payment-auth\.service/);

    // After remediation, verify must succeed
    const authFile = path.join(tmpHome, 'systemd-incident', 'config', 'units', 'payment-auth.service');
    const authContent = fs.readFileSync(authFile, 'utf8').replace(/After=payment-api\.service/, '');
    fs.writeFileSync(authFile, authContent);

    const res2 = runScript(tmpHome, analyzeBin, ['verify']);
    assert.equal(res2.status, 0, 'verify must succeed when cycle is broken');
    assert.match(res2.stdout, /Verification successful: 0 cycles detected/);
    assert.match(res2.stdout, /Topological Execution Order/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-205: separation of ordering directives (After/Before) from requirements (Requires/Wants)', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-205-req-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    // Create a scenario where Unit A Requires Unit B, but B has no ordering relationship
    const unitsDir = path.join(tmpHome, 'systemd-incident', 'config', 'units');
    fs.writeFileSync(path.join(unitsDir, 'req-only-a.service'), '[Unit]\nDescription=Req A\nRequires=req-only-b.service\n\n[Service]\nExecStart=/bin/true\n');
    fs.writeFileSync(path.join(unitsDir, 'req-only-b.service'), '[Unit]\nDescription=Req B\nRequires=req-only-a.service\n\n[Service]\nExecStart=/bin/true\n');

    // Mutual Requires does NOT form an ordering cycle if neither specifies After=/Before=
    // Fix existing cycle first
    const authFile = path.join(unitsDir, 'payment-auth.service');
    fs.writeFileSync(authFile, fs.readFileSync(authFile, 'utf8').replace(/After=payment-api\.service/, ''));

    const analyzeBin = path.join(tmpHome, 'systemd-incident', 'bin', 'systemd-analyze');
    const res = runScript(tmpHome, analyzeBin, ['verify']);
    assert.equal(res.status, 0, 'Mutual Requires without After/Before must not create an ordering cycle');
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});
