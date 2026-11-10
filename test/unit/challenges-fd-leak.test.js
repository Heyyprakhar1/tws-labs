const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');
const { CHALLENGE_SKILLS } = require('../../src/challenge-pages');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'intermediate', 'file-descriptor-limit-exhaustion');
const STEPS = ['diagnose-fd-exhaustion', 'investigate-fd-leak', 'remediate-leak-and-limits', 'verify-fd-recovery'];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const isNode = scriptPath.endsWith('.js') || scriptPath.includes('verify-fds') || scriptPath.includes('worker-daemon');
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
    timeout: 10000,
    encoding: 'utf8',
  });
}

function cleanupProcesses(home) {
  try {
    const pidFile = path.join(home, 'fd-incident', 'var', 'run', 'event-collector.pid');
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

test('LNX-CH-109 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'file-descriptor-limit-exhaustion');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-109');
  assert.equal(challenge.level, 'intermediate');
  assert.equal(challenge.tasksCount, 4);
  assert.equal(challenge.steps.length, 5);
});

test('LNX-CH-109: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['file-descriptor-limit-exhaustion'];
  assert.ok(Array.isArray(skills), 'CH-109 must have skills mapping in CHALLENGE_SKILLS');
  assert.equal(skills.length, 4, 'CH-109 must have exactly four skill labels');
  assert.deepEqual(skills, [
    'File Descriptors',
    'EMFILE Triage',
    'Resource Leaks',
    'LimitNOFILE',
  ]);
});

test('LNX-CH-109: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-flow-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup script failed:\n${setupRes.out}`);

    const base = path.join(tmpHome, 'fd-incident');
    assert.ok(fs.existsSync(path.join(base, 'bin', 'systemctl')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'worker-daemon')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'verify-fds')));

    // All initial checks must fail
    for (const step of STEPS) {
      const checkRes = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(checkRes.status, 0, `Initial check ${step}.sh must fail`);
    }

    // Task 1: diagnose-fd-exhaustion
    const sol1 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[0]}.sh`));
    assert.equal(sol1.status, 0, `Solution 1 failed: ${sol1.stderr}`);
    const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
    assert.equal(chk1.status, 0, `Check 1 failed: ${chk1.stderr}`);

    // Tasks 2-4 must still fail
    for (const step of STEPS.slice(1)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh should fail before its solution`);
    }

    // Task 2: investigate-fd-leak
    const sol2 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[1]}.sh`));
    assert.equal(sol2.status, 0, `Solution 2 failed: ${sol2.stderr}`);
    const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
    assert.equal(chk2.status, 0, `Check 2 failed: ${chk2.stderr}`);

    // Tasks 3-4 must still fail
    for (const step of STEPS.slice(2)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh should fail before its solution`);
    }

    // Task 3: remediate-leak-and-limits
    const sol3 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[2]}.sh`));
    assert.equal(sol3.status, 0, `Solution 3 failed: ${sol3.stderr}`);
    const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`));
    assert.equal(chk3.status, 0, `Check 3 failed: ${chk3.stderr}`);

    // Task 4 must still fail before restart and verify-fds
    const chk4Before = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
    assert.notEqual(chk4Before.status, 0, 'Check 4 must fail before service restart and audit');

    // Task 4: verify-fd-recovery
    const sol4 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[3]}.sh`));
    assert.equal(sol4.status, 0, `Solution 4 failed: ${sol4.stderr}`);
    const chk4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
    assert.equal(chk4.status, 0, `Check 4 failed: ${chk4.stderr}`);

    // All checks must now pass
    for (const step of STEPS) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.equal(c.status, 0, `Check ${step}.sh must pass in final state`);
    }
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-109: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  // Skip-ahead 1: diagnose-fd-exhaustion
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-skip1-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const skip = runScript(tmpHome, path.join(CH_DIR, 'setup', `${STEPS[0]}.sh`));
      assert.equal(skip.status, 0, `Skip 1 failed: ${skip.stderr}`);
      const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
      assert.notEqual(chk1.status, 0);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }

  // Skip-ahead 2: investigate-fd-leak
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-skip2-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const skip = runScript(tmpHome, path.join(CH_DIR, 'setup', `${STEPS[1]}.sh`));
      assert.equal(skip.status, 0, `Skip 2 failed: ${skip.stderr}`);
      const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
      assert.equal(chk1.status, 0);
      const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
      assert.notEqual(chk2.status, 0);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }

  // Skip-ahead 3: remediate-leak-and-limits
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-skip3-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const skip = runScript(tmpHome, path.join(CH_DIR, 'setup', `${STEPS[2]}.sh`));
      assert.equal(skip.status, 0, `Skip 3 failed: ${skip.stderr}`);
      const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
      assert.equal(chk1.status, 0);
      const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
      assert.equal(chk2.status, 0);
      const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`));
      assert.notEqual(chk3.status, 0);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }

  // Skip-ahead 4: verify-fd-recovery
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-skip4-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const skip = runScript(tmpHome, path.join(CH_DIR, 'setup', `${STEPS[3]}.sh`));
      assert.equal(skip.status, 0, `Skip 4 failed: ${skip.stderr}`);
      const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
      assert.equal(chk1.status, 0);
      const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
      assert.equal(chk2.status, 0);
      const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`));
      assert.equal(chk3.status, 0);
      const chk4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
      assert.notEqual(chk4.status, 0);

      const sol4 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[3]}.sh`));
      assert.equal(sol4.status, 0);
      const chk4After = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
      assert.equal(chk4After.status, 0);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }
});

test('LNX-CH-109: dual root-cause enforcement matrix (leak-only vs limit-only failures)', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  // Sub-case A: Limit raised to 4096, but leak left unpatched (AUTO_CLOSE_CHUNKS=false)
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-caseA-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const base = path.join(tmpHome, 'fd-incident');

      const unitFile = path.join(base, 'systemd', 'system', 'event-collector.service');
      fs.writeFileSync(unitFile, fs.readFileSync(unitFile, 'utf8').replace('LimitNOFILE=256', 'LimitNOFILE=4096'));
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['daemon-reload']);
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['restart']);

      const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'remediate-leak-and-limits.sh'));
      assert.notEqual(chk3.status, 0, 'Check 3 must fail when AUTO_CLOSE_CHUNKS is false');

      const verifyRes = runScript(tmpHome, 'fd-incident/bin/verify-fds');
      assert.notEqual(verifyRes.status, 0, 'verify-fds must reject leaking daemon under load');
      assert.match(verifyRes.stderr, /Descriptor leak detected/);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }

  // Sub-case B: Leak patched (AUTO_CLOSE_CHUNKS=true), but limit left at 256
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-caseB-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const base = path.join(tmpHome, 'fd-incident');

      const cfgFile = path.join(base, 'config', 'worker.env');
      fs.writeFileSync(cfgFile, fs.readFileSync(cfgFile, 'utf8').replace('AUTO_CLOSE_CHUNKS=false', 'AUTO_CLOSE_CHUNKS=true'));
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['daemon-reload']);
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['restart']);

      const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'remediate-leak-and-limits.sh'));
      assert.notEqual(chk3.status, 0, 'Check 3 must fail when LimitNOFILE is < 4096');

      const verifyRes = runScript(tmpHome, 'fd-incident/bin/verify-fds');
      assert.notEqual(verifyRes.status, 0, 'verify-fds must reject daemon with limits < 4096');
      assert.match(verifyRes.stderr, /Process limits insufficient/);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }

  // Sub-case C: Both patched (AUTO_CLOSE_CHUNKS=true and LimitNOFILE=4096)
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-caseC-'));
    try {
      sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
      const base = path.join(tmpHome, 'fd-incident');

      const cfgFile = path.join(base, 'config', 'worker.env');
      fs.writeFileSync(cfgFile, fs.readFileSync(cfgFile, 'utf8').replace('AUTO_CLOSE_CHUNKS=false', 'AUTO_CLOSE_CHUNKS=true'));
      const unitFile = path.join(base, 'systemd', 'system', 'event-collector.service');
      fs.writeFileSync(unitFile, fs.readFileSync(unitFile, 'utf8').replace('LimitNOFILE=256', 'LimitNOFILE=4096'));
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['daemon-reload']);
      runScript(tmpHome, 'fd-incident/bin/systemctl', ['restart']);

      const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'remediate-leak-and-limits.sh'));
      assert.equal(chk3.status, 0, 'Check 3 must pass when both fixes are present');

      const verifyRes = runScript(tmpHome, 'fd-incident/bin/verify-fds');
      assert.equal(verifyRes.status, 0, 'verify-fds must pass when both fixes are present');
      assert.match(verifyRes.stdout, /File descriptor limits and leak audit successful/);
    } finally {
      cleanupProcesses(tmpHome);
    }
  }
});

test('LNX-CH-109: service-level LimitNOFILE is inherited by daemon process RLIMIT_NOFILE', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-limits-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'fd-incident');

    const pidFile = path.join(base, 'var', 'run', 'event-collector.pid');
    const pid1 = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    const limits1 = fs.readFileSync(`/proc/${pid1}/limits`, 'utf8');
    const m1 = limits1.match(/^Max open files\s+(\d+)\s+(\d+)/m);
    assert.ok(m1);
    assert.equal(parseInt(m1[1], 10), 256, 'Initial soft limit must be 256');
    assert.equal(parseInt(m1[2], 10), 256, 'Initial hard limit must be 256');

    // Raise LimitNOFILE in unit to 4096 and restart
    const unitFile = path.join(base, 'systemd', 'system', 'event-collector.service');
    fs.writeFileSync(unitFile, fs.readFileSync(unitFile, 'utf8').replace('LimitNOFILE=256', 'LimitNOFILE=4096'));
    runScript(tmpHome, 'fd-incident/bin/systemctl', ['daemon-reload']);
    runScript(tmpHome, 'fd-incident/bin/systemctl', ['restart']);

    const pid2 = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.notEqual(pid1, pid2, 'Restarted worker must have a new PID');
    const limits2 = fs.readFileSync(`/proc/${pid2}/limits`, 'utf8');
    const m2 = limits2.match(/^Max open files\s+(\d+)\s+(\d+)/m);
    assert.ok(m2);
    assert.ok(parseInt(m2[1], 10) >= 4096, 'Restarted soft limit must be >= 4096');
    assert.ok(parseInt(m2[2], 10) >= 4096, 'Restarted hard limit must be >= 4096');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-109: deterministic EMFILE trigger and descriptor-safety bounds', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-emfile-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'fd-incident');

    const pid = parseInt(fs.readFileSync(path.join(base, 'var', 'run', 'event-collector.pid'), 'utf8').trim(), 10);
    const fdCount = fs.readdirSync(`/proc/${pid}/fd`).length;

    assert.ok(fdCount >= 255 && fdCount <= 256, `Initial daemon must have ~256 open file descriptors (got ${fdCount})`);

    const logContent = fs.readFileSync(path.join(base, 'logs', 'worker.log'), 'utf8');
    assert.match(logContent, /EMFILE: too many open files/);
    assert.match(logContent, /code: EMFILE/);
    assert.match(logContent, /syscall: open/);
    assert.match(logContent, /errno: -24/);

    let deletedCount = 0;
    const fds = fs.readdirSync(`/proc/${pid}/fd`);
    for (const fd of fds) {
      try {
        const target = fs.readlinkSync(`/proc/${pid}/fd/${fd}`);
        if (target.includes('chunk-') && target.includes('(deleted)')) {
          deletedCount++;
        }
      } catch {}
    }
    assert.ok(deletedCount >= 200, `Expected >= 200 deleted chunk file descriptors (got ${deletedCount})`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-109: concurrent challenge sessions run isolated without process or file collisions', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-conc-A-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-conc-B-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, homeA, undefined, {}, { isolateOutput: true });
    sandbox.runChallengeSetup(CH_DIR, homeB, undefined, {}, { isolateOutput: true });

    const pidA = parseInt(fs.readFileSync(path.join(homeA, 'fd-incident', 'var', 'run', 'event-collector.pid'), 'utf8').trim(), 10);
    const pidB = parseInt(fs.readFileSync(path.join(homeB, 'fd-incident', 'var', 'run', 'event-collector.pid'), 'utf8').trim(), 10);

    assert.ok(pidA && fs.existsSync(`/proc/${pidA}`), 'Worker A must be running');
    assert.ok(pidB && fs.existsSync(`/proc/${pidB}`), 'Worker B must be running');
    assert.notEqual(pidA, pidB, 'Worker processes must have distinct PIDs');

    // Stopping A must not stop B
    const stopA = runScript(homeA, 'fd-incident/bin/systemctl', ['stop']);
    assert.equal(stopA.status, 0);
    assert.equal(fs.existsSync(`/proc/${pidA}`), false, 'Worker A must be stopped');
    assert.ok(fs.existsSync(`/proc/${pidB}`), 'Worker B must remain running');

    // Stopping B
    const stopB = runScript(homeB, 'fd-incident/bin/systemctl', ['stop']);
    assert.equal(stopB.status, 0);
    assert.equal(fs.existsSync(`/proc/${pidB}`), false, 'Worker B must be stopped');
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});

test('LNX-CH-109: clean process teardown leaves zero orphaned daemon processes', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-109-stop-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'fd-incident');

    const pidFile = path.join(base, 'var', 'run', 'event-collector.pid');
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(fs.existsSync(`/proc/${pid}`), 'Worker daemon must be running before stop');

    const stopRes = runScript(tmpHome, 'fd-incident/bin/systemctl', ['stop']);
    assert.equal(stopRes.status, 0, `systemctl stop failed: ${stopRes.stderr}`);

    assert.equal(fs.existsSync(`/proc/${pid}`), false, `Process ${pid} must be terminated`);
    assert.equal(fs.existsSync(pidFile), false, 'PID file must be removed');
  } finally {
    cleanupProcesses(tmpHome);
  }
});
