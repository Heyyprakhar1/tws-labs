const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { spawnSync } = require('child_process');
const { createChallengeLoader, CHALLENGE_REGISTRY } = require('../../src/challenge-loader');
const { CHALLENGE_SKILLS } = require('../../src/challenge-pages');
const { createSandbox } = require('../../src/sandbox');

const CHALLENGE_DIR = path.join(__dirname, '..', '..', 'challenges', 'linux', 'linux-capabilities-privilege-boundary');

const TARGET_UID = (typeof process.getuid === 'function' && process.getuid() === 0 && process.env.LAB_UID)
  ? Number(process.env.LAB_UID)
  : undefined;

function mkLearnerTmp(prefix) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  if (TARGET_UID !== undefined) {
    try { fs.chownSync(tmp, TARGET_UID, TARGET_UID); } catch {}
  }
  return tmp;
}

function spawnLearner(cmd, args, opts = {}) {
  const extra = TARGET_UID !== undefined ? { uid: TARGET_UID, gid: TARGET_UID } : {};
  return spawnSync(cmd, args, { ...extra, ...opts });
}

function prepareScriptForLearner(srcPath, tmpHome) {
  if (TARGET_UID === undefined) return srcPath;
  const scriptName = `.exec-${path.basename(srcPath)}`;
  const destPath = path.join(tmpHome, scriptName);
  fs.copyFileSync(srcPath, destPath);
  try {
    fs.chownSync(destPath, TARGET_UID, TARGET_UID);
    fs.chmodSync(destPath, 0o755);
  } catch {}
  return destPath;
}

test('LNX-CH-210 loads and validates in registry', () => {
  const loader = createChallengeLoader();
  const c = loader.getChallenge('linux', 'linux-capabilities-privilege-boundary');
  assert.ok(c, 'Challenge LNX-CH-210 not found');
  assert.equal(c.id, 'LNX-CH-210');
  assert.equal(c.slug, 'linux-capabilities-privilege-boundary');
  assert.equal(c.level, 'advanced');
  assert.equal(c.tasksCount, 4);
  assert.equal(c.steps.length, 5);
});

test('LNX-CH-210: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['linux-capabilities-privilege-boundary'];
  assert.ok(Array.isArray(skills));
  assert.ok(skills.includes('Linux Capabilities'));
  assert.ok(skills.includes('CapEff / CapBnd'));
  assert.ok(skills.includes('DAC Boundary'));
  assert.ok(skills.includes('Least Privilege'));
});

test('LNX-CH-210: initial checks fail after setup and pass after solution', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = mkLearnerTmp('tws-ch210-cycle-');

  try {
    const setupRes = sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, TARGET_UID, {});
    assert.equal(setupRes.code, 0, `Setup failed: ${setupRes.out}`);

    const tasks = [
      'audit-capabilities',
      'diagnose-dac-failure',
      'reconfigure-runtime-dir',
      'verify-least-privilege',
    ];

    for (const task of tasks) {
      const checkScript = path.join(CHALLENGE_DIR, 'checks', `${task}.sh`);
      const failRes = await sandbox.runCheck(checkScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(failRes.pass, false, `Task check ${task} unexpectedly passed before solution!`);

      const solScript = prepareScriptForLearner(path.join(CHALLENGE_DIR, 'solutions', `${task}.sh`), tmpHome);
      const solRes = await sandbox.runScript(solScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(solRes.code, 0, `Solution for ${task} failed: ${solRes.out}`);

      const passRes = await sandbox.runCheck(checkScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(passRes.pass, true, `Task check ${task} failed after solution: ${passRes.message}`);
    }
  } finally {
    const stopScript = path.join(tmpHome, 'privilege-incident', 'bin', 'service-daemon');
    if (fs.existsSync(stopScript)) {
      try { spawnLearner(stopScript, ['stop'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' }); } catch {}
    }
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-210: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tasks = [
    'audit-capabilities',
    'diagnose-dac-failure',
    'reconfigure-runtime-dir',
    'verify-least-privilege',
  ];

  for (const targetTask of tasks) {
    const tmpHome = mkLearnerTmp(`tws-ch210-skip-${targetTask}-`);
    try {
      const setupRes = sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, TARGET_UID, {});
      assert.equal(setupRes.code, 0);

      const skipScript = path.join(CHALLENGE_DIR, 'setup', `${targetTask}.sh`);
      assert.ok(fs.existsSync(skipScript), `Missing skip-ahead script: ${skipScript}`);

      const skipRes1 = await sandbox.runScript(skipScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(skipRes1.code, 0, `First skip run failed for ${targetTask}: ${skipRes1.out}`);

      const skipRes2 = await sandbox.runScript(skipScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(skipRes2.code, 0, `Second skip run failed for ${targetTask}: ${skipRes2.out}`);

      const checkScript = path.join(CHALLENGE_DIR, 'checks', `${targetTask}.sh`);
      const checkRes = await sandbox.runCheck(checkScript, { home: tmpHome, uid: TARGET_UID });
      assert.equal(checkRes.pass, true, `Check ${targetTask} failed after skip-ahead setup: ${checkRes.message}`);
    } finally {
      const stopScript = path.join(tmpHome, 'privilege-incident', 'bin', 'service-daemon');
      if (fs.existsSync(stopScript)) {
        try { spawnLearner(stopScript, ['stop'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' }); } catch {}
      }
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  }
});

test('LNX-CH-210: capability-decoder decodes hex bitmasks accurately', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = mkLearnerTmp('tws-ch210-decoder-');

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, TARGET_UID, {});
    const decoder = path.join(tmpHome, 'privilege-incident', 'bin', 'capability-decoder');

    // 1. Decode zero mask
    const r0 = spawnLearner(decoder, ['--mask=0000000000000000'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(r0.status, 0);
    assert.match(r0.stdout, /None \(Empty\)/);

    // 2. Decode bounding set
    const rBnd = spawnLearner(decoder, ['--mask=00000000a80425fb'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(rBnd.status, 0);
    assert.match(rBnd.stdout, /cap_chown/);
    assert.match(rBnd.stdout, /cap_net_bind_service/);
    assert.match(rBnd.stdout, /cap_dac_override/);

    // 3. Inspect live process
    const rLive = spawnLearner(decoder, [], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(rLive.status, 0);
    assert.match(rLive.stdout, /CapEff:/);
    assert.match(rLive.stdout, /CapBnd:/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-210: service-daemon fails cleanly on DAC permission denial against /var/run/app.pid', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = mkLearnerTmp('tws-ch210-dacfail-');

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, TARGET_UID, {});
    const daemon = path.join(tmpHome, 'privilege-incident', 'bin', 'service-daemon');

    // Initial config targets /var/run/app.pid
    // Non-root user writing to /var/run/app.pid gets PermissionError
    const r = spawnLearner(daemon, ['start'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    if (process.getuid() !== 0 || TARGET_UID !== undefined) {
      assert.equal(r.status, 1);
      assert.match(r.stderr, /Permission denied/);
      const logFile = path.join(tmpHome, 'privilege-incident', 'var', 'log', 'service-startup.log');
      assert.ok(fs.existsSync(logFile));
      const logContent = fs.readFileSync(logFile, 'utf8');
      assert.match(logContent, /Permission denied/);
    }
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-210: daemon lifecycle, healthcheck, CapEff verification, and zero orphan processes', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = mkLearnerTmp('tws-ch210-daemon-');

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, TARGET_UID, {});
    const targetDir = path.join(tmpHome, 'privilege-incident');
    const userRunDir = path.join(targetDir, 'var', 'run');
    fs.mkdirSync(userRunDir, { recursive: true });
    if (TARGET_UID !== undefined) {
      try { fs.chownSync(userRunDir, TARGET_UID, TARGET_UID); } catch {}
    }

    // Configure to user runtime dir
    const userPidFile = path.join(userRunDir, 'app.pid');
    fs.writeFileSync(path.join(targetDir, 'config', 'daemon.env'), `
SERVICE_PORT=8085
PID_FILE="${userPidFile}"
SOCKET_PATH="${path.join(userRunDir, 'app.sock')}"
LOG_FILE="${path.join(targetDir, 'var', 'log', 'app.log')}"
RUN_AS_USER="lab0"
`);

    const daemon = path.join(targetDir, 'bin', 'service-daemon');
    const verifyScript = path.join(targetDir, 'bin', 'verify-service');

    // 1. Start daemon
    const startRes = spawnLearner(daemon, ['start'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(startRes.status, 0);

    // 2. Read PID
    assert.ok(fs.existsSync(userPidFile), 'PID file was not created');
    const pid = parseInt(fs.readFileSync(userPidFile, 'utf8').trim(), 10);
    assert.ok(pid > 0);

    // 3. Verify process attributes via /proc/<pid>/status
    const statusPath = `/proc/${pid}/status`;
    assert.ok(fs.existsSync(statusPath), `Process ${pid} is not running`);
    const statusContent = fs.readFileSync(statusPath, 'utf8');
    assert.match(statusContent, /CapEff:\s+0000000000000000/);

    // 4. Run verify runner
    const verifyRes = spawnLearner(verifyScript, [], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(verifyRes.status, 0);
    assert.match(verifyRes.stdout, /Verification SUCCESS/);

    // 5. Clean stop
    const stopRes = spawnLearner(daemon, ['stop'], { env: { ...process.env, HOME: tmpHome }, encoding: 'utf8' });
    assert.equal(stopRes.status, 0);
    assert.ok(!fs.existsSync(userPidFile), 'PID file was not removed after stop');

    // Confirm process is gone
    let isDead = false;
    try {
      process.kill(pid, 0);
    } catch (e) {
      isDead = true;
    }
    assert.ok(isDead, `Process ${pid} still running after stop!`);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});
