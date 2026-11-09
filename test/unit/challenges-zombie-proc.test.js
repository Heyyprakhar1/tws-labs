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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'zombie-process-lifecycle-reaping');
const STEPS = [
  'diagnose-zombie-accumulation',
  'investigate-process-lifecycle',
  'implement-sigchld-reaper',
  'verify-worker-lifecycle',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isPython = basename === 'batch-supervisor' || basename === 'verify-reaping' || basename === 'batch-worker';
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
    const pidFile = path.join(home, 'zombie-incident', 'var', 'run', 'supervisor.pid');
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

test('LNX-CH-206 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'zombie-process-lifecycle-reaping');
  assert.ok(ch, 'zombie-process-lifecycle-reaping must be loadable');
  assert.equal(ch.id, 'LNX-CH-206');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'Zombie Process Accumulation, Lifecycle & SIGCHLD Reaping');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-206: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['zombie-process-lifecycle-reaping'], 'Skills taxonomy must be registered for zombie-process-lifecycle-reaping');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['zombie-process-lifecycle-reaping']));
  assert.ok(CHALLENGE_SKILLS['zombie-process-lifecycle-reaping'].length >= 3);
});

test('LNX-CH-206: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-206-flow-'));

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

test('LNX-CH-206: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-206-skip-${step}-`));
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

test('LNX-CH-206: genuine Linux zombie process accumulation and process table inspection', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-206-zombies-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'zombie-incident', 'var', 'run', 'supervisor.pid');
    assert.ok(fs.existsSync(pidFile));
    const supervisorPid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(supervisorPid > 0);

    // Inspect process table for defunct children of supervisorPid
    const psRes = spawnSync('ps', ['-o', 'pid,ppid,stat,cmd', '-u', String(process.getuid())], { encoding: 'utf8' });
    assert.equal(psRes.status, 0);

    const lines = psRes.stdout.trim().split('\n');
    const zombies = lines.filter(line => {
      const parts = line.trim().split(/\s+/);
      return parts.length >= 3 && parts[1] === String(supervisorPid) && parts[2].includes('Z');
    });

    assert.equal(zombies.length, 10, 'Must have exactly 10 defunct child processes in process table');

    // Bounded child count constraint: total spawned children must never exceed 20
    assert.ok(zombies.length <= 20, 'Zombies must not exceed safe bound of 20');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-206: clean process teardown eliminates supervisor and all defunct children', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-206-teardown-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'zombie-incident', 'var', 'run', 'supervisor.pid');
    assert.ok(fs.existsSync(pidFile));
    const supervisorPid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);

    // Stop supervisor via supervisor-ctl
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'zombie-incident', 'bin', 'supervisor-ctl'), ['stop']);
    assert.equal(stopRes.status, 0);

    // Give time for OS to clean up
    spawnSync('sleep', ['0.3']);

    // Check that supervisor is dead
    let isSupervisorDead = false;
    try {
      process.kill(supervisorPid, 0);
    } catch {
      isSupervisorDead = true;
    }
    assert.ok(isSupervisorDead, `supervisor process ${supervisorPid} must terminate`);

    // Verify all child zombies reparented/reaped
    const psRes = spawnSync('ps', ['-o', 'pid,ppid,stat,cmd', '-u', String(process.getuid())], { encoding: 'utf8' });
    const lingering = psRes.stdout.split('\n').filter(l => l.includes(String(supervisorPid)));
    assert.equal(lingering.length, 0, 'No lingering child processes should remain attached to supervisor');
  } finally {
    cleanupProcesses(tmpHome);
  }
});
