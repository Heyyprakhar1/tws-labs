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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'advanced', 'cgroup-cfs-throttling');
const STEPS = [
  'diagnose-cfs-throttling',
  'correlate-latency-spikes',
  'reconfigure-cpu-quota',
  'verify-latency-recovery',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isPython = basename === 'benchmark-latency' || basename === 'search-indexer' || basename === 'cgroup-metrics';
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
    const pidFile = path.join(home, 'cgroup-incident', 'var', 'run', 'indexer.pid');
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

test('LNX-CH-203 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'cgroup-cfs-throttling');
  assert.ok(ch, 'cgroup-cfs-throttling must be loadable');
  assert.equal(ch.id, 'LNX-CH-203');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'Cgroup v2 CFS Bandwidth Throttling & Latency Triage');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-203: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['cgroup-cfs-throttling'], 'Skills taxonomy must be registered for cgroup-cfs-throttling');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['cgroup-cfs-throttling']));
  assert.ok(CHALLENGE_SKILLS['cgroup-cfs-throttling'].length >= 3);
});

test('LNX-CH-203: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-203-flow-'));

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

test('LNX-CH-203: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-203-skip-${step}-`));
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

test('LNX-CH-203: bimodal latency telemetry correctly models 100ms CFS period stall', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-203-bimodal-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const latFile = path.join(tmpHome, 'cgroup-incident', 'logs', 'latency.log');
    assert.ok(fs.existsSync(latFile));
    const lines = fs.readFileSync(latFile, 'utf8').trim().split('\n');
    assert.ok(lines.length >= 20);

    const lats = lines.map(line => {
      const m = line.match(/total_latency_ms=([0-9.]+)/);
      return m ? parseFloat(m[1]) : 0;
    });

    const base = lats.filter(x => x < 10);
    const spikes = lats.filter(x => x >= 100);
    assert.ok(base.length >= 5, 'Must contain baseline queries ~4ms');
    assert.ok(spikes.length >= 5, 'Must contain throttled queries ~104ms');

    const avgBase = base.reduce((a, b) => a + b, 0) / base.length;
    const avgSpike = spikes.reduce((a, b) => a + b, 0) / spikes.length;
    const delta = avgSpike - avgBase;
    assert.ok(delta >= 98.0 && delta <= 102.0, `Delta (${delta}ms) must match ~100ms CFS period`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-203: clean process teardown leaves zero orphaned daemon processes', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-203-teardown-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'cgroup-incident', 'var', 'run', 'indexer.pid');
    assert.ok(fs.existsSync(pidFile));
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(pid > 0);

    // Stop daemon via ctl
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'cgroup-incident', 'bin', 'search-ctl'), ['stop']);
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
    assert.ok(isDead, `search-indexer process ${pid} must terminate cleanly`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});
