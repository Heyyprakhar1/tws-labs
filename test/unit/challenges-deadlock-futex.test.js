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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'advanced', 'multi-thread-deadlock-futex');
const STEPS = [
  'diagnose-deadlock-threads',
  'correlate-lock-inversion',
  'remediate-lock-ordering',
  'verify-concurrent-throughput',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const isPython = scriptPath.endsWith('.py');
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

function cleanupProcesses(home) {
  try {
    const pidFile = path.join(home, 'deadlock-incident', 'var', 'service.pid');
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

test('LNX-CH-207 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'multi-thread-deadlock-futex');
  assert.ok(ch, 'multi-thread-deadlock-futex must be loadable');
  assert.equal(ch.id, 'LNX-CH-207');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'Multi-Thread Deadlock, AB-BA Lock Inversion & Futex Tracing');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-207: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['multi-thread-deadlock-futex'], 'Skills taxonomy must be registered');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['multi-thread-deadlock-futex']));
  assert.ok(CHALLENGE_SKILLS['multi-thread-deadlock-futex'].length >= 3);
});

test('LNX-CH-207: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-flow-'));

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
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-207: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-207-skip-${step}-`));
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
      cleanupProcesses(tmpHome);
    }
  }
});

test('LNX-CH-207: genuine AB-BA deadlock reproduction and live /proc futex wait-channel verification', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-deadlock-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'deadlock-incident', 'var', 'service.pid');
    assert.ok(fs.existsSync(pidFile));
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(pid > 0);

    // Verify process is running
    assert.equal(process.kill(pid, 0), true);

    // Inspect threads under /proc/<pid>/task
    const taskDir = `/proc/${pid}/task`;
    assert.ok(fs.existsSync(taskDir));
    const tids = fs.readdirSync(taskDir).filter((t) => t !== String(pid));
    assert.ok(tids.length >= 2, `Expected at least 2 worker threads, found ${tids.length}`);

    // Verify futex wait channel on worker threads
    let futexCount = 0;
    for (const tid of tids) {
      const wchanPath = path.join(taskDir, tid, 'wchan');
      if (fs.existsSync(wchanPath)) {
        const wchan = fs.readFileSync(wchanPath, 'utf8').trim();
        if (wchan.includes('futex')) {
          futexCount++;
        }
      }
    }
    assert.ok(futexCount >= 2, `Expected at least 2 threads blocked in futex wait channel, observed ${futexCount}`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-207: lock-order remediation enables concurrent transactions with zero deadlocks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-remedy-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    // Remediate lock ordering
    const remedySol = runScript(tmpHome, path.join(CH_DIR, 'solutions', 'remediate-lock-ordering.sh'));
    assert.equal(remedySol.status, 0);

    // Run benchmark concurrency
    const benchSol = runScript(tmpHome, path.join(CH_DIR, 'solutions', 'verify-concurrent-throughput.sh'));
    assert.equal(benchSol.status, 0, `Benchmark failed:\n${benchSol.stderr}\n${benchSol.stdout}`);

    // Verify recovery report
    const reportFile = path.join(tmpHome, 'deadlock-incident', 'reports', 'recovery-report.env');
    assert.ok(fs.existsSync(reportFile));
    const content = fs.readFileSync(reportFile, 'utf8');
    assert.match(content, /BENCHMARK_STATUS=SUCCESS/);
    assert.match(content, /TRANSFERS_COMPLETED=50/);
    assert.match(content, /DEADLOCKS_DETECTED=0/);
    assert.match(content, /LOCK_ORDERING=DETERMINISTIC/);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-207: bounded watchdog and clean process teardown eliminates all worker threads', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-teardown-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'deadlock-incident', 'var', 'service.pid');
    assert.ok(fs.existsSync(pidFile));
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);

    // Stop service
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'deadlock-incident', 'bin', 'order-ctl'), ['stop']);
    assert.equal(stopRes.status, 0);

    // Verify process is terminated
    let isDead = false;
    try {
      process.kill(pid, 0);
    } catch {
      isDead = true;
    }
    assert.ok(isDead, `Service process ${pid} must be terminated`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-207: concurrent learner session isolation', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-isoA-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-207-isoB-'));

  try {
    const sA = sandbox.runChallengeSetup(CH_DIR, homeA, undefined, {}, { isolateOutput: true });
    const sB = sandbox.runChallengeSetup(CH_DIR, homeB, undefined, {}, { isolateOutput: true });
    assert.equal(sA.code, 0);
    assert.equal(sB.code, 0);

    const pidFileA = path.join(homeA, 'deadlock-incident', 'var', 'service.pid');
    const pidFileB = path.join(homeB, 'deadlock-incident', 'var', 'service.pid');
    const pidA = parseInt(fs.readFileSync(pidFileA, 'utf8').trim(), 10);
    const pidB = parseInt(fs.readFileSync(pidFileB, 'utf8').trim(), 10);

    assert.notEqual(pidA, pidB, 'Concurrent sessions must run under distinct PIDs');
    assert.equal(process.kill(pidA, 0), true);
    assert.equal(process.kill(pidB, 0), true);

    // Remediate A, leave B untouched
    const remedyA = runScript(homeA, path.join(CH_DIR, 'solutions', 'remediate-lock-ordering.sh'));
    assert.equal(remedyA.status, 0);

    const checkA = runScript(homeA, path.join(CH_DIR, 'checks', 'remediate-lock-ordering.sh'));
    assert.equal(checkA.status, 0);

    // Check B must still fail (remediation in A must not affect B)
    const checkB = runScript(homeB, path.join(CH_DIR, 'checks', 'remediate-lock-ordering.sh'));
    assert.notEqual(checkB.status, 0);
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});
