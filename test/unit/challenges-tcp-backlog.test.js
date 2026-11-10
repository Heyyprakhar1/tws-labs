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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'advanced', 'tcp-accept-queue-saturation');
const STEPS = [
  'diagnose-accept-queue',
  'measure-kernel-drops',
  'reconfigure-socket-backlog',
  'verify-backlog-resilience',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isPython = basename === 'verify-backlog' || basename === 'api-server' || basename === 'netstat-metrics' || basename === 'burst-client';
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
    const sPidFile = path.join(home, 'tcp-incident', 'var', 'run', 'api-server.pid');
    const cPidFile = path.join(home, 'tcp-incident', 'var', 'run', 'clients.pid');
    for (const pf of [sPidFile, cPidFile]) {
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

test('LNX-CH-202 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const challenge = loader.getChallenge('linux', 'tcp-accept-queue-saturation');
  assert.ok(challenge, 'Challenge must load');
  assert.equal(challenge.id, 'LNX-CH-202');
  assert.equal(challenge.level, 'advanced');
  assert.equal(challenge.tasksCount, 4);
  assert.equal(challenge.steps.length, 5);
});

test('LNX-CH-202: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['tcp-accept-queue-saturation'];
  assert.ok(Array.isArray(skills), 'CH-202 must have skills mapping in CHALLENGE_SKILLS');
  assert.equal(skills.length, 4, 'CH-202 must have exactly four skill labels');
  assert.deepEqual(skills, [
    'TCP Sockets',
    'Accept Queue',
    'ListenOverflows',
    'Backlog Sizing',
  ]);
});

test('LNX-CH-202: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-flow-'));
  const testEnv = { PORT_TCP: '18290' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup script failed:\n${setupRes.out}`);

    const base = path.join(tmpHome, 'tcp-incident');
    assert.ok(fs.existsSync(path.join(base, 'bin', 'api-ctl')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'api-server')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'netstat-metrics')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'burst-client')));
    assert.ok(fs.existsSync(path.join(base, 'bin', 'verify-backlog')));
    assert.ok(fs.existsSync(path.join(base, 'config', 'api.env')));

    // Initial checks 1-4 must fail
    for (const step of STEPS) {
      const checkRes = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`), testEnv);
      assert.notEqual(checkRes.status, 0, `Initial check ${step}.sh must fail`);
    }

    // Step 1: diagnose-accept-queue
    const sol1 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[0]}.sh`), testEnv);
    assert.equal(sol1.status, 0, `Solution 1 failed: ${sol1.stderr}`);
    const chk1 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[0]}.sh`), testEnv);
    assert.equal(chk1.status, 0, `Check 1 failed: ${chk1.stderr}`);

    // Steps 2-4 must still fail
    for (const step of STEPS.slice(1)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`), testEnv);
      assert.notEqual(c.status, 0, `Check ${step}.sh must fail before solution`);
    }

    // Step 2: measure-kernel-drops
    const sol2 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[1]}.sh`), testEnv);
    assert.equal(sol2.status, 0, `Solution 2 failed: ${sol2.stderr}`);
    const chk2 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[1]}.sh`), testEnv);
    assert.equal(chk2.status, 0, `Check 2 failed: ${chk2.stderr}`);

    // Steps 3-4 must still fail
    for (const step of STEPS.slice(2)) {
      const c = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`), testEnv);
      assert.notEqual(c.status, 0, `Check ${step}.sh must fail before solution`);
    }

    // Step 3: reconfigure-socket-backlog
    const sol3 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[2]}.sh`), testEnv);
    assert.equal(sol3.status, 0, `Solution 3 failed: ${sol3.stderr}`);
    const chk3 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[2]}.sh`), testEnv);
    assert.equal(chk3.status, 0, `Check 3 failed: ${chk3.stderr}`);

    // Step 4 must still fail
    const c4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`), testEnv);
    assert.notEqual(c4.status, 0, `Check 4 must fail before solution`);

    // Step 4: verify-backlog-resilience
    const sol4 = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${STEPS[3]}.sh`), testEnv);
    assert.equal(sol4.status, 0, `Solution 4 failed: ${sol4.stderr}`);
    const chk4 = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[3]}.sh`), testEnv);
    assert.equal(chk4.status, 0, `Check 4 failed: ${chk4.stderr}`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-skip-'));
  const testEnv = { PORT_TCP: '18291' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0, `Setup failed:\n${setupRes.out}`);

    // Test each skip-ahead step
    for (let i = 0; i < STEPS.length; i++) {
      const step = STEPS[i];
      const setupScript = path.join(CH_DIR, 'setup', `${step}.sh`);
      assert.ok(fs.existsSync(setupScript), `Skip setup script for ${step} must exist`);

      // Run twice for idempotency
      const r1 = runScript(tmpHome, setupScript, testEnv);
      assert.equal(r1.status, 0, `Skip setup for ${step} (run 1) failed: ${r1.stderr}`);
      const r2 = runScript(tmpHome, setupScript, testEnv);
      assert.equal(r2.status, 0, `Skip setup for ${step} (run 2) failed: ${r2.stderr}`);

      // All previous steps must pass
      for (let prev = 0; prev < i; prev++) {
        const prevChk = runScript(tmpHome, path.join(CH_DIR, 'checks', `${STEPS[prev]}.sh`), testEnv);
        assert.equal(prevChk.status, 0, `Previous check ${STEPS[prev]} should pass after skipping to ${step}`);
      }

      // Current step should fail before its solution (except step 1 if clean)
      if (i > 0 && i < STEPS.length - 1) {
        const curChk = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`), testEnv);
        assert.notEqual(curChk.status, 0, `Check ${step} must fail before solution even after skip setup`);
      }

      // Run current step solution
      const sol = runScript(tmpHome, path.join(CH_DIR, 'solutions', `${step}.sh`), testEnv);
      assert.equal(sol.status, 0, `Solution for ${step} failed after skip: ${sol.stderr}`);
      const curChkPass = runScript(tmpHome, path.join(CH_DIR, 'checks', `${step}.sh`), testEnv);
      assert.equal(curChkPass.status, 0, `Check ${step} must pass after its solution`);
    }
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: genuine accept queue inspection via ss and kernel overflow counters', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-queue-'));
  const testEnv = { PORT_TCP: '18292' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    // Run ss -lnt on test port
    const ssRes = spawnSync('ss', ['-lnt', 'sport = :18292'], { encoding: 'utf8' });
    assert.equal(ssRes.status, 0);
    assert.ok(ssRes.stdout.includes(':18292'));

    // Check Send-Q is 5 (configured backlog)
    const lines = ssRes.stdout.trim().split('\n').filter((l) => l.includes(':18292'));
    assert.equal(lines.length, 1);
    const cols = lines[0].trim().split(/\s+/);
    // Columns: State Recv-Q Send-Q Local Address:Port ...
    const recvQ = parseInt(cols[1], 10);
    const sendQ = parseInt(cols[2], 10);
    assert.equal(sendQ, 5, 'Send-Q must reflect listen backlog 5');
    assert.ok(recvQ >= 5 && recvQ <= 6, `Recv-Q must reflect saturated queue (5 or 6), got ${recvQ}`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: concurrent challenge sessions run isolated on offset ports without socket collision', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const homeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-sessA-'));
  const homeB = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-sessB-'));
  const envA = { PORT_TCP: '18293' };
  const envB = { PORT_TCP: '18294' };

  try {
    const sA = sandbox.runChallengeSetup(CH_DIR, homeA, undefined, envA, { isolateOutput: true });
    const sB = sandbox.runChallengeSetup(CH_DIR, homeB, undefined, envB, { isolateOutput: true });
    assert.equal(sA.code, 0);
    assert.equal(sB.code, 0);

    const ssA = spawnSync('ss', ['-lnt', 'sport = :18293'], { encoding: 'utf8' });
    const ssB = spawnSync('ss', ['-lnt', 'sport = :18294'], { encoding: 'utf8' });
    assert.ok(ssA.stdout.includes(':18293'), 'Session A must be listening on 18293');
    assert.ok(ssB.stdout.includes(':18294'), 'Session B must be listening on 18294');

    // Stopping service in session A does not affect session B
    const stopA = runScript(homeA, path.join(homeA, 'tcp-incident', 'bin', 'api-ctl'), ['stop']);
    assert.equal(stopA.status, 0);

    const ssA2 = spawnSync('ss', ['-lnt', 'sport = :18293'], { encoding: 'utf8' });
    const ssB2 = spawnSync('ss', ['-lnt', 'sport = :18294'], { encoding: 'utf8' });
    assert.equal(ssA2.stdout.includes(':18293'), false, 'Session A port must be released');
    assert.ok(ssB2.stdout.includes(':18294'), 'Session B port must still be active');
  } finally {
    cleanupProcesses(homeA);
    cleanupProcesses(homeB);
  }
});

test('LNX-CH-202: clean process teardown leaves zero orphaned daemon processes', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-teardown-'));
  const testEnv = { PORT_TCP: '18295' };

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pidFile = path.join(tmpHome, 'tcp-incident', 'var', 'run', 'api-server.pid');
    assert.ok(fs.existsSync(pidFile));
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(pid > 0);

    // Stop daemon via ctl
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'tcp-incident', 'bin', 'api-ctl'), ['stop']);
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
    assert.ok(isDead, `api-server process ${pid} must terminate cleanly`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: solution contains zero fabricated Recv-Q or Send-Q fallbacks', () => {
  const solPath = path.join(CH_DIR, 'solutions', 'diagnose-accept-queue.sh');
  const content = fs.readFileSync(solPath, 'utf8');

  // Must not contain any fabricated fallback assignments
  assert.doesNotMatch(content, /RECV_Q\s*=\s*["']?6["']?/, 'Must not contain hardcoded RECV_Q=6 assignment');
  assert.doesNotMatch(content, /OBSERVED_SEND_Q\s*=\s*["']?5["']?/, 'Must not contain hardcoded OBSERVED_SEND_Q=5 assignment');
  assert.doesNotMatch(content, /-lt\s+5/, 'Must not contain fallback threshold condition (-lt 5)');
  assert.doesNotMatch(content, /\|\|\s*\[\s*-z\s*"\$RECV_Q"\s*\]/, 'Must not contain fallback default replacement');

  // Must genuinely invoke ss -lnt and write parsed variables
  assert.match(content, /ss\s+-lnt/, 'Must invoke ss -lnt');
  assert.match(content, /OBSERVED_RECV_Q=\$RECV_Q/, 'Must assign dynamic RECV_Q variable');
  assert.match(content, /OBSERVED_SEND_Q=\$SEND_Q/, 'Must assign dynamic SEND_Q variable');
});

test('LNX-CH-202: diagnosis fails honestly when listening socket is inactive', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-nosock-'));
  const testEnv = { PORT_TCP: '18296' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    // Stop the service so port is not listening
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'tcp-incident', 'bin', 'api-ctl'), ['stop']);
    assert.equal(stopRes.status, 0);

    // Solution must fail with exit code != 0
    const solRes = runScript(tmpHome, path.join(CH_DIR, 'solutions', 'diagnose-accept-queue.sh'), testEnv);
    assert.notEqual(solRes.status, 0, 'Solution must fail when socket is not listening');
    assert.ok(
      solRes.stderr.includes('No listening socket found') || solRes.stderr.includes('Error'),
      `Should report missing socket diagnostic: ${solRes.stderr}`
    );
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: diagnosis fails honestly when accept queue is unsaturated', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-unsat-'));
  const testEnv = { PORT_TCP: '18297' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    // Restart service cleanly so accept queue is empty (0/5)
    const restartRes = runScript(tmpHome, path.join(tmpHome, 'tcp-incident', 'bin', 'api-ctl'), ['restart']);
    assert.equal(restartRes.status, 0);

    // Verify queue is unsaturated via ss
    const ssRes = spawnSync('ss', ['-lnt', 'sport = :18297'], { encoding: 'utf8' });
    assert.ok(ssRes.stdout.includes(':18297'));
    const line = ssRes.stdout.trim().split('\n').find((l) => l.includes(':18297'));
    const cols = line.trim().split(/\s+/);
    const recvQ = parseInt(cols[1], 10);
    assert.equal(recvQ, 0, 'Accept queue should be 0 after clean restart');

    // Solution must fail because queue is not saturated
    const solRes = runScript(tmpHome, path.join(CH_DIR, 'solutions', 'diagnose-accept-queue.sh'), testEnv);
    assert.notEqual(solRes.status, 0, 'Solution must fail when queue is unsaturated');
    assert.ok(
      solRes.stderr.includes('not saturated'),
      `Should report unsaturated queue diagnostic: ${solRes.stderr}`
    );
  } finally {
    cleanupProcesses(tmpHome);
  }
});

test('LNX-CH-202: controlled burst triggers genuine ListenOverflows and ListenDrops deltas', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-202-drops-'));
  const testEnv = { PORT_TCP: '18298' };

  try {
    const setupRes = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, testEnv, { isolateOutput: true });
    assert.equal(setupRes.code, 0);

    function getNetstat() {
      const netstat = fs.readFileSync('/proc/net/netstat', 'utf8');
      const lines = netstat.split('\n').filter((l) => l.startsWith('TcpExt:')).map((l) => l.trim().split(/\s+/));
      if (lines.length < 2) return { overflows: 0, drops: 0 };
      const headers = lines[0].slice(1);
      const values = lines[1].slice(1).map(Number);
      const map = Object.fromEntries(headers.map((h, idx) => [h, values[idx]]));
      return { overflows: map.ListenOverflows || 0, drops: map.ListenDrops || 0 };
    }

    const before = getNetstat();

    // Run burst-client 20
    const burstRes = runScript(tmpHome, path.join(tmpHome, 'tcp-incident', 'bin', 'burst-client'), ['20'], testEnv);
    assert.equal(burstRes.status, 0, `burst-client failed: ${burstRes.stderr}`);
    assert.ok(burstRes.stdout.includes('6 succeeded, 14 dropped'), `Should report 6 succeeded, 14 dropped:\n${burstRes.stdout}`);

    const after = getNetstat();
    const overflowDelta = after.overflows - before.overflows;
    const dropDelta = after.drops - before.drops;

    assert.equal(overflowDelta, 14, `ListenOverflows delta must be exactly 14, got ${overflowDelta}`);
    assert.equal(dropDelta, 14, `ListenDrops delta must be exactly 14, got ${dropDelta}`);
  } finally {
    cleanupProcesses(tmpHome);
  }
});
