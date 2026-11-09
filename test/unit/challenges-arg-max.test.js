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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'directory-spool-arg-max');
const STEPS = [
  'diagnose-spool-bloat',
  'inspect-arg-limits',
  'reclaim-spool-storage',
  'verify-spool-recovery',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isNode = scriptPath.endsWith('.js') || basename === 'verify-spool' || basename === 'spool-daemon';
  const cmd = isNode ? 'node' : 'bash';
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

function cleanupProcesses(home) {
  try {
    const pidFile = path.join(home, 'spool-incident', 'var', 'run', 'spooler.pid');
    if (fs.existsSync(pidFile)) {
      const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
      if (pid) {
        try { process.kill(pid, 'SIGKILL'); } catch {}
      }
    }
  } catch {}
  try {
    fs.rmSync(home, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-201 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'directory-spool-arg-max');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-201');
  assert.equal(challenge.level, 'advanced');
  assert.equal(challenge.tasksCount, 4);
  assert.equal(challenge.steps.length, 5);
});

test('LNX-CH-201: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['directory-spool-arg-max'];
  assert.ok(Array.isArray(skills), 'CH-201 must have skills mapping in CHALLENGE_SKILLS');
  assert.equal(skills.length, 4, 'CH-201 must have exactly four skill labels');
  assert.deepEqual(skills, [
    'Argument Limits',
    'E2BIG',
    'find -delete',
    'Directory Bloat',
  ]);
});

test('LNX-CH-201: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-flow-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup script failed:\n${setupRes.out}`);

    const base = path.join(tmpHome, 'spool-incident');
    assert.ok(fs.existsSync(path.join(base, 'bin', 'spool-ctl')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'spool-daemon')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'verify-spool')));
    assert.ok(fs.existsSync(path.join(base, 'config', 'spooler.env')));
    assert.ok(fs.existsSync(path.join(base, 'var', 'spool')));

    // Initial checks 1-4 must fail
    for (const step of STEPS) {
      const checkRes = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(checkRes.status, 0, `Initial check ${step}.sh must fail`);
    }

    // Step 1: diagnose-spool-bloat
    const sol1 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[0]}.sh`));
    assert.equal(sol1.status, 0, `Solution 1 failed: ${sol1.stderr}`);
    const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
    assert.equal(chk1.status, 0, `Check 1 failed: ${chk1.stderr}`);

    // Steps 2-4 must still fail
    for (const step of STEPS.slice(1)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh must fail before solution`);
    }

    // Step 2: inspect-arg-limits
    const sol2 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[1]}.sh`));
    assert.equal(sol2.status, 0, `Solution 2 failed: ${sol2.stderr}`);
    const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
    assert.equal(chk2.status, 0, `Check 2 failed: ${chk2.stderr}`);

    // Steps 3-4 must still fail
    for (const step of STEPS.slice(2)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh must fail before solution`);
    }

    // Step 3: reclaim-spool-storage
    const sol3 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[2]}.sh`));
    assert.equal(sol3.status, 0, `Solution 3 failed: ${sol3.stderr}`);
    const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`));
    assert.equal(chk3.status, 0, `Check 3 failed: ${chk3.stderr}`);

    // Step 4 must still fail
    const c4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
    assert.notEqual(c4.status, 0, `Check 4 must fail before solution`);

    // Step 4: verify-spool-recovery
    const sol4 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[3]}.sh`));
    assert.equal(sol4.status, 0, `Solution 4 failed: ${sol4.stderr}`);
    const chk4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
    assert.equal(chk4.status, 0, `Check 4 failed: ${chk4.stderr}`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-201: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-skip-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup failed:\n${setupRes.out}`);

    // Test each skip-ahead step
    for (let i = 0; i < STEPS.length; i++) {
      const step = STEPS[i];
      const setupScript = path.join(CH_DIR, 'setup', `${step}.sh`);
      assert.ok(fs.existsSync(setupScript), `Skip setup script for ${step} must exist`);

      // Run twice for idempotency
      const r1 = runScript(tmpHome, setupScript);
      assert.equal(r1.status, 0, `Skip setup for ${step} (run 1) failed: ${r1.stderr}`);
      const r2 = runScript(tmpHome, setupScript);
      assert.equal(r2.status, 0, `Skip setup for ${step} (run 2) failed: ${r2.stderr}`);

      // All previous steps must pass
      for (let prev = 0; prev < i; prev++) {
        const prevChk = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[prev]}.sh`));
        assert.equal(prevChk.status, 0, `Previous check ${STEPS[prev]} should pass after skipping to ${step}`);
      }

      // Current step should fail before its solution (except step 1 if clean)
      if (i > 0 && i < STEPS.length - 1) {
        const curChk = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
        assert.notEqual(curChk.status, 0, `Check ${step} must fail before solution even after skip setup`);
      }

      // Run current step solution
      const sol = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${step}.sh`));
      assert.equal(sol.status, 0, `Solution for ${step} failed after skip: ${sol.stderr}`);
      const curChkPass = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.equal(curChkPass.status, 0, `Check ${step} must pass after its solution`);
    }
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-201: genuine E2BIG reproduction via shell glob expansion and NAME_MAX safety', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-e2big-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    const spoolDir = path.join(tmpHome, 'spool-incident', 'var', 'spool');
    const files = fs.readdirSync(spoolDir);
    assert.equal(files.length, 10000, 'Must have exactly 10,000 files in staging spool');

    // Verify all filenames are within NAME_MAX (255 bytes)
    for (const f of files.slice(0, 100)) {
      assert.ok(Buffer.byteLength(f) <= 255, `Filename ${f.slice(0, 20)}... exceeds NAME_MAX 255`);
      assert.equal(Buffer.byteLength(f), 245, `Filename length must be exactly 245 bytes`);
    }

    // Verify executing rm * fails with E2BIG (exit code 126 or 'Argument list too long')
    const rmTest = spawnSync('bash', ['-c', 'cd "$1" && /bin/rm *', '--', spoolDir], {
      cwd: spoolDir,
      timeout: 10000,
      encoding: 'utf8',
    });
    assert.notEqual(rmTest.status, 0, 'rm * must fail due to argument list overflow');
    assert.ok(
      rmTest.stderr.includes('Argument list too long') || rmTest.status === 126,
      `Expected Argument list too long / exit 126, got: ${rmTest.stderr}`
    );

    // Verify find -delete succeeds safely
    const findTest = spawnSync('find', [spoolDir, '-type', 'f', '-name', 'batch_*.dat', '-delete'], {
      cwd: spoolDir,
      timeout: 10000,
      encoding: 'utf8',
    });
    assert.equal(findTest.status, 0, `find -delete must succeed: ${findTest.stderr}`);
    assert.equal(fs.readdirSync(spoolDir).length, 0, 'Spool must be empty after find -delete');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-201: concurrent challenge sessions run isolated without file collisions', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-sessA-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-sessB-'));

  try {
    const sA = sandbox.runChallengeSetup(CH_DIR, homeA, undefined, {}, { isolateOutput: true });
    const sB = sandbox.runChallengeSetup(CH_DIR, homeB, undefined, {}, { isolateOutput: true });
    assert.equal(sA.code, 0);
    assert.equal(sB.code, 0);

    const spoolA = path.join(homeA, 'spool-incident', 'var', 'spool');
    const spoolB = path.join(homeB, 'spool-incident', 'var', 'spool');
    assert.equal(fs.readdirSync(spoolA).length, 10000);
    assert.equal(fs.readdirSync(spoolB).length, 10000);

    // Deleting files in session A does not affect session B
    const delA = runScript(homeA, path.join(CH_DIR, 'solutions', 'reclaim-spool-storage.sh'));
    assert.equal(delA.status, 0);
    assert.equal(fs.readdirSync(spoolA).length, 0);
    assert.equal(fs.readdirSync(spoolB).length, 10000);
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});

test('LNX-CH-201: clean process teardown leaves zero orphaned daemon processes', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-201-teardown-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'spool-incident', 'var', 'run', 'spooler.pid');
    assert.ok(fs.existsSync(pidFile));
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(pid > 0);

    // Stop daemon via ctl
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'spool-incident', 'bin', 'spool-ctl'), ['stop']);
    assert.equal(stopRes.status, 0);

    let isDead = false;
    for (let i = 0; i < 20; i++) {
      try {
        process.kill(pid, 0);
        spawnSync('sleep', ['0.1']);
      } catch {
        isDead = true;
        break;
      }
    }
    assert.ok(isDead, `spooler process ${pid} must terminate cleanly`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});
