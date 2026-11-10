const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { createSandbox } = require('../../src/sandbox');
const { createChallengeLoader } = require('../../src/challenge-loader');
const { CHALLENGE_SKILLS } = require('../../src/challenge-pages');
const { createLocalProcessRuntime, cleanupShmOfUid } = require('../../src/runtime');

const CHALLENGES_ROOT = path.join(__dirname, '..', '..', 'challenges');
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'advanced', 'posix-shm-leak-lifecycle');
const STEPS = [
  'diagnose-shm-leak',
  'analyze-shm-lifecycle',
  'remediate-shm-leak',
  'verify-resilient-lifecycle',
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

function cleanupShmAndHome(home, uid = process.getuid()) {
  try {
    const pidFile = path.join(home, 'shm-incident', 'var', 'telemetry.pid');
    if (fs.existsSync(pidFile)) {
      const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
      if (pid) {
        try { process.kill(pid, 'SIGKILL'); } catch {}
      }
    }
  } catch {}
  cleanupShmOfUid('/dev/shm', uid);
  try {
    fs.rmSync(home, { recursive: true, force: true });
  } catch {}
}

test('LNX-CH-208 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'posix-shm-leak-lifecycle');
  assert.ok(ch, 'posix-shm-leak-lifecycle must be loadable');
  assert.equal(ch.id, 'LNX-CH-208');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'POSIX Shared Memory Leaks & Lifecycle Management');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-208: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['posix-shm-leak-lifecycle'], 'Skills taxonomy must be registered');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['posix-shm-leak-lifecycle']));
  assert.ok(CHALLENGE_SKILLS['posix-shm-leak-lifecycle'].length >= 3);
});

test('LNX-CH-208: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-208-flow-'));

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
    cleanupShmAndHome(tmpHome);
  }
});

test('LNX-CH-208: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-208-skip-${step}-`));
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
      cleanupShmAndHome(tmpHome);
    }
  }
});

test('LNX-CH-208: genuine POSIX shared memory creation and initial leaked 1 MB segment', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-208-init-'));
  const uid = process.getuid();
  const shmPath = `/dev/shm/tws_${uid}_telemetry`;

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    // Verify /dev/shm contains the leaked segment
    assert.ok(fs.existsSync(shmPath), `Expected ${shmPath} to exist on /dev/shm`);
    const stat = fs.statSync(shmPath);
    assert.equal(stat.size, 1048576, 'Leaked segment must be exactly 1 MB (1048576 bytes)');
    assert.equal(stat.uid, uid, `Segment owner must match current UID (${uid})`);
  } finally {
    cleanupShmAndHome(tmpHome);
  }
});

test('LNX-CH-208: shm_unlink removes name from /dev/shm but mapping remains visible in /proc/maps as (deleted)', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-208-maps-'));
  const uid = process.getuid();
  const demoShmPath = `/dev/shm/tws_${uid}_lifecycle_demo`;

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    // Start demo daemon
    const startRes = runScript(tmpHome, path.join(tmpHome, 'shm-incident', 'bin', 'demo-lifecycle'), ['start']);
    assert.equal(startRes.status, 0);

    const pidFile = path.join(tmpHome, 'shm-incident', 'var', 'demo.pid');
    assert.ok(fs.existsSync(pidFile));
    const demoPid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);
    assert.ok(demoPid > 0);

    // Verify name was unlinked from /dev/shm
    assert.equal(fs.existsSync(demoShmPath), false, 'shm_unlink must remove the name from /dev/shm');

    // Verify /proc/<pid>/maps retains active deleted mapping
    const mapsContent = fs.readFileSync(`/proc/${demoPid}/maps`, 'utf8');
    const hasDeletedMapping = mapsContent.split('\n').some((line) =>
      line.includes(`tws_${uid}_lifecycle_demo`) && line.includes('(deleted)')
    );
    assert.ok(hasDeletedMapping, `Expected /proc/${demoPid}/maps to contain deleted lifecycle_demo mapping`);

    // Stop demo daemon
    runScript(tmpHome, path.join(tmpHome, 'shm-incident', 'bin', 'demo-lifecycle'), ['stop']);
  } finally {
    cleanupShmAndHome(tmpHome);
  }
});

test('LNX-CH-208: SIGKILL leaves named stale object in /dev/shm and defensive restart recovers cleanly', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-208-sigkill-'));
  const uid = process.getuid();
  const shmPath = `/dev/shm/tws_${uid}_telemetry`;

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    // Configure defensive startup and auto unlink
    const sol3 = runScript(tmpHome, path.join(CH_DIR, 'solutions', 'remediate-shm-leak.sh'));
    assert.equal(sol3.status, 0);

    const pidFile = path.join(tmpHome, 'shm-incident', 'var', 'telemetry.pid');
    const pid = parseInt(fs.readFileSync(pidFile, 'utf8').trim(), 10);

    // Forcibly kill with SIGKILL (bypassing userspace signal handlers)
    process.kill(pid, 'SIGKILL');
    fs.rmSync(pidFile, { force: true });

    // Object should still remain in /dev/shm because SIGKILL prevents atexit / signal handlers
    assert.ok(fs.existsSync(shmPath), 'Object must persist in /dev/shm following SIGKILL');

    // Start daemon again: defensive startup must detect stale segment, unlink it, and start cleanly
    const startRes = runScript(tmpHome, path.join(tmpHome, 'shm-incident', 'bin', 'telemetry-ctl'), ['start']);
    assert.equal(startRes.status, 0);

    // Stop daemon gracefully
    const stopRes = runScript(tmpHome, path.join(tmpHome, 'shm-incident', 'bin', 'telemetry-ctl'), ['stop']);
    assert.equal(stopRes.status, 0);

    // Graceful stop with AUTO_UNLINK_ON_SHUTDOWN=true must cleanly remove the segment
    assert.equal(fs.existsSync(shmPath), false, 'Segment must be unlinked following graceful SIGTERM shutdown');
  } finally {
    cleanupShmAndHome(tmpHome);
  }
});

test('LNX-CH-208: runtime.cleanupSession removes exact tws_${UID}_* objects and preserves other UIDs', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const runtime = createLocalProcessRuntime({ cfg: {}, sandbox, bootstrap: 'bash' });

  // Use a simulated temporary shm directory to test isolation across arbitrary mock UIDs
  const mockShmDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-mock-shm-'));
  const mockHomeA = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-home-a-'));

  try {
    const uidA = process.getuid();
    const uidB = uidA + 999; // Mock distinct UID

    const fileA1 = path.join(mockShmDir, `tws_${uidA}_telemetry`);
    const fileA2 = path.join(mockShmDir, `tws_${uidA}_resilience`);
    const fileB = path.join(mockShmDir, `tws_${uidB}_telemetry`);
    const unrelatedFile = path.join(mockShmDir, `unrelated_${uidA}_test`);

    fs.writeFileSync(fileA1, 'segA1');
    fs.writeFileSync(fileA2, 'segA2');
    fs.writeFileSync(fileB, 'segB');
    fs.writeFileSync(unrelatedFile, 'unrelated');

    // Run cleanupSession for uidA using mockShmDir
    runtime.cleanupSession({
      uid: uidA,
      home: mockHomeA,
      shmDir: mockShmDir,
    });

    // Verify files belonging to uidA with prefix tws_${uidA}_ were removed
    assert.equal(fs.existsSync(fileA1), false, `fileA1 (${fileA1}) must be removed`);
    assert.equal(fs.existsSync(fileA2), false, `fileA2 (${fileA2}) must be removed`);

    // Verify file belonging to uidB was NOT removed
    assert.ok(fs.existsSync(fileB), 'Objects belonging to other UIDs must not be removed');

    // Verify unrelated file was NOT removed
    assert.ok(fs.existsSync(unrelatedFile), 'Non-tws prefixed files must not be removed');
  } finally {
    try { fs.rmSync(mockShmDir, { recursive: true, force: true }); } catch {}
    try { fs.rmSync(mockHomeA, { recursive: true, force: true }); } catch {}
  }
});

test('LNX-CH-208: cleanupShmOfUid is idempotent, non-throwing on missing files, and race-safe', () => {
  const mockShmDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-mock-shm-idemp-'));
  const uid = process.getuid();

  try {
    // Calling on an empty directory should succeed without errors
    assert.doesNotThrow(() => cleanupShmOfUid(mockShmDir, uid));

    // Calling on nonexistent directory should fail closed / gracefully
    assert.doesNotThrow(() => cleanupShmOfUid(path.join(mockShmDir, 'nonexistent'), uid));

    // Calling with null / undefined uid should be a safe no-op
    assert.doesNotThrow(() => cleanupShmOfUid(mockShmDir, null));
    assert.doesNotThrow(() => cleanupShmOfUid(mockShmDir, undefined));

    // Repeated invocations on existing files must be completely idempotent
    const file1 = path.join(mockShmDir, `tws_${uid}_test`);
    fs.writeFileSync(file1, 'data');
    cleanupShmOfUid(mockShmDir, uid);
    assert.equal(fs.existsSync(file1), false);
    cleanupShmOfUid(mockShmDir, uid); // Second invocation: should be a clean no-op
  } finally {
    try { fs.rmSync(mockShmDir, { recursive: true, force: true }); } catch {}
  }
});
