const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawnSync, spawn } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'intermediate', 'port-socket-binding-conflict');
const STEPS = ['triage-socket-conflict', 'terminate-rogue-listener', 'reconfigure-proxy-bindings', 'verify-sockets'];

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

function cleanupProcesses(home) {
  try {
    for (const name of ['rogue-listener', 'auth-proxy']) {
      const pidFile = path.join(home, 'port-incident', 'var', 'run', `${name}.pid`);
      if (fs.existsSync(pidFile)) {
        const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
        if (pid) process.kill(pid, 'SIGKILL');
      }
    }
  } catch {}
  try {
    fs.rmSync(home, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-106 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'port-socket-binding-conflict');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-106');
  assert.equal(challenge.level, 'intermediate');
  assert.equal(challenge.tasksCount, 4);
});

test('LNX-CH-106: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-flow-'));
  const testEnv = { PORT_HTTP: '18210', PORT_METRICS: '19210' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup must exit 0: ${setupRes.out}`);

    // All checks must fail initially
    for (const step of STEPS) {
      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const before = runScript(tmpHome, checkPath, testEnv);
      assert.notEqual(before.status, 0, `Check ${step} must fail before solution: ${before.stdout}`);
    }

    // Solutions and checks in sequence
    for (const step of STEPS) {
      const solPath = path.join(CH_DIR, 'solutions', `${step}.sh`);
      const solRes = runScript(tmpHome, solPath, testEnv);
      assert.equal(solRes.status, 0, `Solution ${step} must exit 0: ${solRes.stderr || solRes.stdout}`);

      const checkPath = path.join(CH_DIR, 'checks', `${step}.sh`);
      const after = runScript(tmpHome, checkPath, testEnv);
      assert.equal(after.status, 0, `Check ${step} must pass after solution: ${after.stderr || after.stdout}`);
    }
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (let i = 0; i < STEPS.length; i++) {
    const targetStep = STEPS[i];
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-106-skip-${i}-`));
    const testEnv = { PORT_HTTP: String(18310 + i), PORT_METRICS: String(19310 + i) };

    try {
      const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
      assert.equal(setupRes.code, 0, `Setup for skip ${targetStep} must exit 0`);

      const skipScript = path.join(CH_DIR, 'setup', `${targetStep}.sh`);

      // First execution
      const skipRes = runScript(tmpHome, skipScript, testEnv);
      assert.equal(skipRes.status, 0, `Skip-ahead ${targetStep} must exit 0: ${skipRes.stderr || skipRes.stdout}`);

      // Idempotency: second execution
      const skipRes2 = runScript(tmpHome, skipScript, testEnv);
      assert.equal(skipRes2.status, 0, `Skip-ahead ${targetStep} must be idempotent`);

      // All prior steps must pass
      for (let j = 0; j < i; j++) {
        const priorCheck = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[j]}.sh`), testEnv);
        assert.equal(priorCheck.status, 0, `Prior step ${STEPS[j]} must pass after skipping to ${targetStep}`);
      }

      // Target step must fail before solution
      const targetBefore = runScript(tmpHome, path.join(CH_DIR, 'checks', `${targetStep}.sh`), testEnv);
      assert.notEqual(targetBefore.status, 0, `Target ${targetStep} must fail before solution`);

      // Target solution
      const solRes = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${targetStep}.sh`), testEnv);
      assert.equal(solRes.status, 0, `Solution for ${targetStep} must exit 0`);

      // Target check must now pass
      const targetAfter = runScript(tmpHome, path.join(CH_DIR, 'checks', `${targetStep}.sh`), testEnv);
      assert.equal(targetAfter.status, 0, `Target ${targetStep} must pass after solution`);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }
});

test('LNX-CH-106: kill-listener process termination helper enforces session UID, start time, socket binding, and process identity', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-kill-'));
  const testEnv = { PORT_HTTP: '18410', PORT_METRICS: '19410' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    const killBin = path.join(tmpHome, 'port-incident', 'bin', 'kill-listener');
    const identFile = path.join(tmpHome, 'port-incident', 'var', 'run', '.rogue-listener.identity');

    assert.ok(fs.existsSync(identFile), 'Setup must write .rogue-listener.identity');
    const origIdent = fs.readFileSync(identFile, 'utf8');

    function runKill(arg) {
      return spawnSync('bash', [killBin, ...(arg !== undefined ? [String(arg)] : [])], {
        cwd: tmpHome,
        env: { ...process.env, HOME: tmpHome, ...testEnv },
        encoding: 'utf8',
      });
    }

    // 1. PID 1 is rejected
    const r1 = runKill(1);
    assert.notEqual(r1.status, 0);
    assert.match(r1.stderr, /does not match recorded session rogue-listener PID|not owned by current session user/);

    // 2. Same-session sleep process is rejected
    const sleepChild = spawn('sleep', ['60']);
    try {
      const r2 = runKill(sleepChild.pid);
      assert.notEqual(r2.status, 0);
      assert.match(r2.stderr, /does not match recorded session rogue-listener PID|not rogue-listener/);
    } finally {
      sleepChild.kill('SIGKILL');
    }

    // 3. Incorrect PID is rejected
    const r3 = runKill(999999);
    assert.notEqual(r3.status, 0);
    assert.match(r3.stderr, /does not match recorded session rogue-listener PID/);

    // 4. Modified or mismatched recorded start time is rejected
    fs.writeFileSync(identFile, origIdent.replace(/STARTTIME=\d+/, 'STARTTIME=99999999'));
    const r4 = runKill();
    assert.notEqual(r4.status, 0);
    assert.match(r4.stderr, /start time mismatch/);
    fs.writeFileSync(identFile, origIdent);

    // 5. Listener bound to a different port is rejected
    fs.writeFileSync(identFile, origIdent.replace(/PORT=\d+/, 'PORT=19999'));
    const r5 = runKill();
    assert.notEqual(r5.status, 0);
    assert.match(r5.stderr, /does not own listening socket on port 19999/);
    fs.writeFileSync(identFile, origIdent);

    // 6. Correct listener can be terminated cleanly
    const r6 = runKill();
    assert.equal(r6.status, 0);
    assert.match(r6.stdout, /Terminated rogue-listener/);

    // 7. Process exited case is handled safely
    const r7 = runKill();
    assert.equal(r7.status, 0);
    assert.match(r7.stdout, /is not running/);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: identity initialization fails closed when /proc/self/stat is unavailable or invalid', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-failstat-'));

  try {
    const res = sandbox.runChallengeSetup(
      CH_DIR,
      tmpHome,
      undefined,
      { PORT_HTTP: '18710', PORT_METRICS: '19710', TEST_MOCK_STAT_ERROR: '1' },
      { isolateOutput: true, timeout: 5000 }
    );
    assert.notEqual(res.code, 0, 'Setup must fail when start time cannot be acquired');
    assert.match(res.out, /rogue-listener failed to start and bind port/);
    assert.equal(fs.existsSync(path.join(tmpHome, 'port-incident', 'var', 'run', '.rogue-listener.identity')), false);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: rogue-listener fails closed, cleans up partial files, and releases port if identity file write fails', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-failident-'));
  const testPort = '18730';
  const testEnv = {
    PORT_HTTP: testPort,
    PORT_METRICS: '19730',
    TEST_MOCK_IDENTITY_WRITE_ERROR: '1',
  };

  try {
    const res = sandbox.runChallengeSetup(
      CH_DIR,
      tmpHome,
      undefined,
      testEnv,
      { isolateOutput: true, timeout: 5000 }
    );
    assert.notEqual(res.code, 0, 'Setup must fail when identity file write fails');
    assert.match(res.out, /rogue-listener failed to start and bind port/);
    assert.match(res.out, /Failed to write identity record/);

    const identFile = path.join(tmpHome, 'port-incident', 'var', 'run', '.rogue-listener.identity');
    const pidFile = path.join(tmpHome, 'port-incident', 'var', 'run', 'rogue-listener.pid');
    const refFile = path.join(tmpHome, 'port-incident', 'var', 'run', '.rogue-listener.ref');
    assert.equal(fs.existsSync(identFile), false, 'Identity file must not exist');
    assert.equal(fs.existsSync(pidFile), false, 'PID file must not exist');
    assert.equal(fs.existsSync(refFile), false, 'Ref file must not exist');

    // Confirm socket on testPort is not bound
    const isBound = await new Promise((resolve) => {
      const req = http.get(`http://127.0.0.1:${testPort}`, () => {
        resolve(true);
      });
      req.on('error', () => {
        resolve(false);
      });
      req.setTimeout(500, () => {
        req.destroy();
        resolve(false);
      });
    });
    assert.equal(isBound, false, `Port ${testPort} must not be listening after fail-closed exit`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: SIGKILL fallback executes only after full re-validation if process ignores SIGTERM', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-sigkill-'));
  const testEnv = { PORT_HTTP: '18720', PORT_METRICS: '19720', TEST_IGNORE_SIGTERM: '1' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0, 'Setup must succeed');

    const killBin = path.join(tmpHome, 'port-incident', 'bin', 'kill-listener');
    const roguePid = parseInt(fs.readFileSync(path.join(tmpHome, 'port-incident', 'var', 'run', 'rogue-listener.pid'), 'utf8').trim(), 10);

    // 1. Process must be alive initially
    assert.doesNotThrow(() => process.kill(roguePid, 0), 'Rogue listener must be running initially');

    // 2. Execute kill-listener (which will send SIGTERM, wait grace period, re-validate, and send SIGKILL)
    const startMs = Date.now();
    const killRes = spawnSync('bash', [killBin], {
      cwd: tmpHome,
      env: { ...process.env, HOME: tmpHome, ...testEnv },
      encoding: 'utf8',
    });
    const elapsedMs = Date.now() - startMs;

    assert.equal(killRes.status, 0, `kill-listener should succeed via SIGKILL fallback: ${killRes.stderr}`);
    assert.match(killRes.stdout, /Terminated rogue-listener/);
    // Grace period was 15 * 0.1s = 1.5s
    assert.ok(elapsedMs >= 1200, `Must have waited for SIGTERM grace period before SIGKILL fallback (elapsed ${elapsedMs}ms)`);

    // 3. Process must now be confirmed terminated
    let isDead = false;
    try {
      process.kill(roguePid, 0);
    } catch {
      isDead = true;
    }
    assert.equal(isDead, true, 'Process must be dead after SIGKILL fallback');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: kill-listener aborts SIGKILL fallback if target identity changes before fallback', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-race-'));
  const testEnv = { PORT_HTTP: '18740', PORT_METRICS: '19740', TEST_IGNORE_SIGTERM: '1' };
  let unrelatedChild = null;

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0, 'Setup must succeed');

    const killBin = path.join(tmpHome, 'port-incident', 'bin', 'kill-listener');
    const roguePid = parseInt(fs.readFileSync(path.join(tmpHome, 'port-incident', 'var', 'run', 'rogue-listener.pid'), 'utf8').trim(), 10);

    // 1. Rogue listener must be alive initially
    assert.doesNotThrow(() => process.kill(roguePid, 0), 'Rogue listener must be running initially');

    // 2. Spawn an unrelated session process to verify it is untouched
    unrelatedChild = spawn('sleep', ['60']);
    assert.ok(unrelatedChild.pid, 'Unrelated process must be spawned');

    // 3. Execute kill-listener with identity corrupt hook to simulate identity change during wait / before SIGKILL
    const killRes = spawnSync('bash', [killBin], {
      cwd: tmpHome,
      env: {
        ...process.env,
        HOME: tmpHome,
        ...testEnv,
        TEST_HOOK_CORRUPT_IDENTITY_BEFORE_KILL: '1',
      },
      encoding: 'utf8',
    });

    // 4. Must exit non-zero and report identity change before SIGKILL
    assert.notEqual(killRes.status, 0, 'kill-listener must fail when target identity changes before SIGKILL');
    assert.match(killRes.stderr, /identity changed before SIGKILL\. Fallback aborted/);

    // 5. Rogue listener must NOT have been killed by fallback SIGKILL
    assert.doesNotThrow(() => process.kill(roguePid, 0), 'Target process must not be killed when identity changes');

    // 6. Unrelated process must NOT be killed
    assert.doesNotThrow(() => process.kill(unrelatedChild.pid, 0), 'Unrelated process must remain alive');
  } finally {
    if (unrelatedChild && unrelatedChild.pid) {
      try { process.kill(unrelatedChild.pid, 'SIGKILL'); } catch {}
    }
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-106: concurrent sessions run independently on offset ports without socket collision', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-conc-A-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-106-conc-B-'));

  try {
    const resA = sandbox.runChallengeSetup(CH_DIR, homeA, undefined, { PORT_HTTP: '18101', PORT_METRICS: '19101' }, { isolateOutput: true });
    assert.equal(resA.code, 0, `Setup A failed: ${resA.out}`);

    const resB = sandbox.runChallengeSetup(CH_DIR, homeB, undefined, { PORT_HTTP: '18102', PORT_METRICS: '19102' }, { isolateOutput: true });
    assert.equal(resB.code, 0, `Setup B failed: ${resB.out}`);

    const pidA = fs.readFileSync(path.join(homeA, 'port-incident', 'var', 'run', 'rogue-listener.pid'), 'utf8').trim();
    const pidB = fs.readFileSync(path.join(homeB, 'port-incident', 'var', 'run', 'rogue-listener.pid'), 'utf8').trim();
    assert.notEqual(pidA, pidB, 'PIDs must be distinct');

    // Run all solutions in Session A
    for (const step of STEPS) {
      const sol = runScript(homeA, path.join(CH_DIR, 'solutions', `${step}.sh`));
      assert.equal(sol.status, 0, `Session A solution ${step} failed`);
      const chk = runScript(homeA, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.equal(chk.status, 0, `Session A check ${step} failed`);
    }

    // Run all solutions in Session B
    for (const step of STEPS) {
      const sol = runScript(homeB, path.join(CH_DIR, 'solutions', `${step}.sh`));
      assert.equal(sol.status, 0, `Session B solution ${step} failed`);
      const chk = runScript(homeB, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.equal(chk.status, 0, `Session B check ${step} failed`);
    }
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});
