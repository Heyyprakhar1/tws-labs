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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'memory-pressure-oom-killer');
const STEPS = [
  'diagnose-memory-pressure',
  'forensic-oom-triage',
  'remediate-memory-limits',
  'verify-memory-recovery',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isNode = scriptPath.endsWith('.js') || basename === 'verify-memory' || basename === 'data-aggregator-worker';
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
    const sPidFile = path.join(home, 'mem-incident', 'var', 'run', 'supervisor.pid');
    const wPidFile = path.join(home, 'mem-incident', 'var', 'run', 'worker.pid');
    for (const pf of [sPidFile, wPidFile]) {
      if (fs.existsSync(pf)) {
        const pid = parseInt(fs.readFileSync(pf, 'utf8').trim(), 10);
        if (pid) {
          try { process.kill(pid, 'SIGKILL'); } catch {}
        }
      }
    }
  } catch {}
  try {
    fs.rmSync(home, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-110 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'memory-pressure-oom-killer');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-110');
  assert.equal(challenge.level, 'intermediate');
  assert.equal(challenge.tasksCount, 4);
  assert.equal(challenge.steps.length, 5);
});

test('LNX-CH-110: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['memory-pressure-oom-killer'];
  assert.ok(Array.isArray(skills), 'CH-110 must have skills mapping in CHALLENGE_SKILLS');
  assert.equal(skills.length, 4, 'CH-110 must have exactly four skill labels');
  assert.deepEqual(skills, [
    'Memory Pressure',
    'OOM Killer',
    'Cgroup Telemetry',
    'Workload Bounding',
  ]);
});

test('LNX-CH-110: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-flow-'));

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup script failed:\n${setupRes.out}`);

    const base = path.join(tmpHome, 'mem-incident');
    assert.ok(fs.existsSync(path.join(base, 'bin', 'systemctl')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'data-aggregator-supervisor')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'data-aggregator-worker')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'verify-memory')));

    // All initial checks must fail
    for (const step of STEPS) {
      const checkRes = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(checkRes.status, 0, `Initial check ${step}.sh must fail`);
    }

    // Task 1: diagnose-memory-pressure
    const sol1 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[0]}.sh`));
    assert.equal(sol1.status, 0, `Solution 1 failed: ${sol1.stderr}`);
    const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`));
    assert.equal(chk1.status, 0, `Check 1 failed: ${chk1.stderr}`);

    // Tasks 2-4 must still fail
    for (const step of STEPS.slice(1)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh should fail before its solution`);
    }

    // Task 2: forensic-oom-triage
    const sol2 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[1]}.sh`));
    assert.equal(sol2.status, 0, `Solution 2 failed: ${sol2.stderr}`);
    const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`));
    assert.equal(chk2.status, 0, `Check 2 failed: ${chk2.stderr}`);

    // Tasks 3-4 must still fail
    for (const step of STEPS.slice(2)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`));
      assert.notEqual(c.status, 0, `Check ${step}.sh should fail before its solution`);
    }

    // Task 3: remediate-memory-limits
    const sol3 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[2]}.sh`));
    assert.equal(sol3.status, 0, `Solution 3 failed: ${sol3.stderr}`);
    const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`));
    assert.equal(chk3.status, 0, `Check 3 failed: ${chk3.stderr}`);

    // Task 4 must still fail before verify-memory
    const chk4Before = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`));
    assert.notEqual(chk4Before.status, 0, 'Check 4 must fail before service restart and verification');

    // Task 4: verify-memory-recovery
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

test('LNX-CH-110: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  // Skip-ahead 1: diagnose-memory-pressure
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-skip1-'));
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

  // Skip-ahead 2: forensic-oom-triage
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-skip2-'));
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

  // Skip-ahead 3: remediate-memory-limits
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-skip3-'));
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

  // Skip-ahead 4: verify-memory-recovery
  {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-skip4-'));
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

test('LNX-CH-110: supervisor recovers when worker child is terminated with SIGKILL (exit 137)', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-sigkill-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'mem-incident');

    const sPidFile = path.join(base, 'var', 'run', 'supervisor.pid');
    const wPidFile = path.join(base, 'var', 'run', 'worker.pid');

    const sPid = parseInt(fs.readFileSync(sPidFile, 'utf8').trim(), 10);
    const wPid = parseInt(fs.readFileSync(wPidFile, 'utf8').trim(), 10);
    assert.ok(sPid && fs.existsSync(`/proc/${sPid}`), 'Supervisor must be running');
    assert.ok(wPid && fs.existsSync(`/proc/${wPid}`), 'Worker must be running');

    // Simulate OOM SIGKILL termination of worker child
    try {
      process.kill(wPid, 'SIGKILL');
    } catch (e) {
      assert.fail(`Failed to send SIGKILL to worker: ${e.message}`);
    }

    // Wait for supervisor to detect exit and restart worker
    await new Promise((r) => setTimeout(r, 600));

    // Supervisor must have survived
    assert.ok(fs.existsSync(`/proc/${sPid}`), 'Supervisor must remain running after worker SIGKILL');

    // Worker must have been respawned with a new PID
    const newWPid = parseInt(fs.readFileSync(wPidFile, 'utf8').trim(), 10);
    assert.notEqual(newWPid, wPid, 'Respawned worker must have a new PID');
    assert.ok(fs.existsSync(`/proc/${newWPid}`), 'New worker must be running');

    // Supervisor log should record the exit 137 / SIGKILL event
    const sLog = fs.readFileSync(path.join(base, 'logs', 'supervisor.log'), 'utf8');
    assert.match(sLog, /exit code 137|terminated with exit code 137|SIGKILL/);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-110: relative victim-selection bias (WORKER_OOM_SCORE_ADJ differential)', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-oomadj-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'mem-incident');

    const sPidFile = path.join(base, 'var', 'run', 'supervisor.pid');
    const wPidFile = path.join(base, 'var', 'run', 'worker.pid');

    const sPid = parseInt(fs.readFileSync(sPidFile, 'utf8').trim(), 10);
    const wPid = parseInt(fs.readFileSync(wPidFile, 'utf8').trim(), 10);

    // Initial worker and supervisor share the same baseline oom_score_adj
    const initSAdj = parseInt(fs.readFileSync(`/proc/${sPid}/oom_score_adj`, 'utf8').trim(), 10);
    const initWAdj = parseInt(fs.readFileSync(`/proc/${wPid}/oom_score_adj`, 'utf8').trim(), 10);
    assert.equal(initWAdj, initSAdj, 'Initial worker and supervisor must share baseline oom_score_adj');

    // Apply remediated configuration setting WORKER_OOM_SCORE_ADJ=500
    const cfgPath = path.join(base, 'config', 'worker.env');
    fs.writeFileSync(cfgPath, fs.readFileSync(cfgPath, 'utf8').replace('WORKER_OOM_SCORE_ADJ=0', 'WORKER_OOM_SCORE_ADJ=500'));

    // Restart service
    runScript(tmpHome, 'mem-incident/bin/systemctl', ['daemon-reload']);
    runScript(tmpHome, 'mem-incident/bin/systemctl', ['restart', 'data-aggregator']);

    const newWPid = parseInt(fs.readFileSync(wPidFile, 'utf8').trim(), 10);
    const newSPid = parseInt(fs.readFileSync(sPidFile, 'utf8').trim(), 10);

    const remediatedSAdj = parseInt(fs.readFileSync(`/proc/${newSPid}/oom_score_adj`, 'utf8').trim(), 10);
    const remediatedWAdj = parseInt(fs.readFileSync(`/proc/${newWPid}/oom_score_adj`, 'utf8').trim(), 10);

    assert.equal(remediatedSAdj, initSAdj, 'Supervisor must retain initial baseline oom_score_adj');
    assert.equal(remediatedWAdj, 500, 'Remediated worker must have oom_score_adj 500');
    assert.ok(remediatedWAdj > remediatedSAdj, 'Differential must establish positive victim bias towards worker');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-110: verification runner measures bounded peak RSS under load', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-load-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'mem-incident');

    // Apply remediated config
    const cfgPath = path.join(base, 'config', 'worker.env');
    let cfg = fs.readFileSync(cfgPath, 'utf8');
    cfg = cfg.replace('BATCH_SIZE=50000', 'BATCH_SIZE=500');
    cfg = cfg.replace('MAX_CONCURRENCY=16', 'MAX_CONCURRENCY=2');
    cfg = cfg.replace('BUFFER_MODE=unbounded', 'BUFFER_MODE=stream');
    cfg = cfg.replace('MAX_MEMORY_MB=1024', 'MAX_MEMORY_MB=128');
    cfg = cfg.replace('WORKER_OOM_SCORE_ADJ=0', 'WORKER_OOM_SCORE_ADJ=500');
    fs.writeFileSync(cfgPath, cfg);

    runScript(tmpHome, 'mem-incident/bin/systemctl', ['daemon-reload']);
    runScript(tmpHome, 'mem-incident/bin/systemctl', ['restart', 'data-aggregator']);

    // Run verify-memory
    const verifyRes = runScript(tmpHome, 'mem-incident/bin/verify-memory');
    assert.equal(verifyRes.status, 0, `verify-memory failed:\n${verifyRes.stderr}\n${verifyRes.stdout}`);
    assert.match(verifyRes.stdout, /AUDIT PASSED/);
    assert.match(verifyRes.stdout, /50\/50 batches processed/);

    const markerPath = path.join(base, 'reports', '.memory-verified');
    assert.ok(fs.existsSync(markerPath), '.memory-verified must be created');

    const markerContent = fs.readFileSync(markerPath, 'utf8');
    assert.match(markerContent, /^TOTAL_BATCHES=50$/m);
    assert.match(markerContent, /^MAX_CONCURRENCY=2$/m);
    assert.match(markerContent, /^STATUS=PASSED$/m);

    const m = markerContent.match(/^PEAK_RSS_KB=(\d+)$/m);
    assert.ok(m, 'PEAK_RSS_KB must be recorded');
    const peakRss = parseInt(m[1], 10);
    assert.ok(peakRss >= 40000, `Peak RSS (${peakRss} kB) must be >= 40 MB`);
    assert.ok(peakRss <= 92160, `Peak RSS (${peakRss} kB) must be <= 90 MB`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-110: verification marker SHA-256 integrity validation fails on tampering or corruption', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-tamper-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });

    // Solve tasks 1-4 legitimately first
    for (const step of STEPS) {
      runScript(tmpHome, path.join(CH_DIR, 'solutions', `${step}.sh`));
    }
    const checkBefore = runScript(tmpHome, path.join(CH_DIR, 'checks', 'verify-memory-recovery.sh'));
    assert.equal(checkBefore.status, 0, 'Initial check 4 must pass before tampering');

    const base = path.join(tmpHome, 'mem-incident');
    const markerPath = path.join(base, 'reports', '.memory-verified');
    const originalMarker = fs.readFileSync(markerPath, 'utf8');

    // Tamper 1: modify PEAK_RSS_KB without updating checksum
    fs.writeFileSync(markerPath, originalMarker.replace(/^PEAK_RSS_KB=\d+$/m, 'PEAK_RSS_KB=150000'));
    const chkT1 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'verify-memory-recovery.sh'));
    assert.notEqual(chkT1.status, 0, 'Tampered peak RSS must fail check');
    assert.match(chkT1.stdout, /Integrity check failed/);

    // Tamper 2: corrupt CHECKSUM
    fs.writeFileSync(markerPath, originalMarker.replace(/^CHECKSUM=.+$/m, 'CHECKSUM=0000000000000000000000000000000000000000000000000000000000000000'));
    const chkT2 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'verify-memory-recovery.sh'));
    assert.notEqual(chkT2.status, 0, 'Corrupted checksum must fail check');
    assert.match(chkT2.stdout, /Integrity check failed/);

    // Tamper 3: remove marker file entirely
    fs.unlinkSync(markerPath);
    const chkT3 = runScript(tmpHome, path.join(CH_DIR, 'checks', 'verify-memory-recovery.sh'));
    assert.notEqual(chkT3.status, 0, 'Missing marker must fail check');

    // Restore original marker
    fs.writeFileSync(markerPath, originalMarker);
    const chkRestored = runScript(tmpHome, path.join(CH_DIR, 'checks', 'verify-memory-recovery.sh'));
    assert.equal(chkRestored.status, 0, 'Restored marker must pass check');
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-110: concurrent challenge sessions run isolated without socket or process collisions', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-conc-A-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-conc-B-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, homeA, undefined, {}, { isolateOutput: true });
    sandbox.runChallengeSetup(CH_DIR, homeB, undefined, {}, { isolateOutput: true });

    const sPidA = parseInt(fs.readFileSync(path.join(homeA, 'mem-incident', 'var', 'run', 'supervisor.pid'), 'utf8').trim(), 10);
    const wPidA = parseInt(fs.readFileSync(path.join(homeA, 'mem-incident', 'var', 'run', 'worker.pid'), 'utf8').trim(), 10);

    const sPidB = parseInt(fs.readFileSync(path.join(homeB, 'mem-incident', 'var', 'run', 'supervisor.pid'), 'utf8').trim(), 10);
    const wPidB = parseInt(fs.readFileSync(path.join(homeB, 'mem-incident', 'var', 'run', 'worker.pid'), 'utf8').trim(), 10);

    assert.ok(sPidA && fs.existsSync(`/proc/${sPidA}`), 'Supervisor A must be running');
    assert.ok(wPidA && fs.existsSync(`/proc/${wPidA}`), 'Worker A must be running');
    assert.ok(sPidB && fs.existsSync(`/proc/${sPidB}`), 'Supervisor B must be running');
    assert.ok(wPidB && fs.existsSync(`/proc/${wPidB}`), 'Worker B must be running');

    assert.notEqual(sPidA, sPidB, 'Supervisors must have distinct PIDs');
    assert.notEqual(wPidA, wPidB, 'Workers must have distinct PIDs');

    // Stopping Session A must not terminate Session B
    const stopA = runScript(homeA, 'mem-incident/bin/systemctl', ['stop']);
    assert.equal(stopA.status, 0);
    assert.equal(fs.existsSync(`/proc/${sPidA}`), false, 'Supervisor A must be stopped');
    assert.equal(fs.existsSync(`/proc/${wPidA}`), false, 'Worker A must be stopped');

    assert.ok(fs.existsSync(`/proc/${sPidB}`), 'Supervisor B must remain running');
    assert.ok(fs.existsSync(`/proc/${wPidB}`), 'Worker B must remain running');

    // Stopping Session B
    const stopB = runScript(homeB, 'mem-incident/bin/systemctl', ['stop']);
    assert.equal(stopB.status, 0);
    assert.equal(fs.existsSync(`/proc/${sPidB}`), false, 'Supervisor B must be stopped');
    assert.equal(fs.existsSync(`/proc/${wPidB}`), false, 'Worker B must be stopped');
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});

test('LNX-CH-110: clean process teardown leaves zero orphaned daemon processes', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-110-stop-'));

  try {
    sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    const base = path.join(tmpHome, 'mem-incident');

    const sPidFile = path.join(base, 'var', 'run', 'supervisor.pid');
    const wPidFile = path.join(base, 'var', 'run', 'worker.pid');

    const sPid = parseInt(fs.readFileSync(sPidFile, 'utf8').trim(), 10);
    const wPid = parseInt(fs.readFileSync(wPidFile, 'utf8').trim(), 10);

    assert.ok(fs.existsSync(`/proc/${sPid}`), 'Supervisor must be running before stop');
    assert.ok(fs.existsSync(`/proc/${wPid}`), 'Worker must be running before stop');

    const stopRes = runScript(tmpHome, 'mem-incident/bin/systemctl', ['stop']);
    assert.equal(stopRes.status, 0, `systemctl stop failed: ${stopRes.stderr}`);

    assert.equal(fs.existsSync(`/proc/${sPid}`), false, `Supervisor ${sPid} must be terminated`);
    assert.equal(fs.existsSync(`/proc/${wPid}`), false, `Worker ${wPid} must be terminated`);
    assert.equal(fs.existsSync(sPidFile), false, 'Supervisor PID file must be removed');
    assert.equal(fs.existsSync(wPidFile), false, 'Worker PID file must be removed');
  } finally {
    cleanupProcesses(tmpHome);
  }
});
