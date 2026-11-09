const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const {
  createExecutionRuntime,
  createLocalProcessRuntime,
  cleanupShmOfSession,
  reconcileDeadInstances,
  getProcStartTime,
  getBootId,
  isProcessAliveWithStartTime,
} = require('../../src/runtime');
const { createSandbox } = require('../../src/sandbox');
const { parseProcEnviron, isProtectedPid, killSessionProcesses } = require('../../src/lib');

test('LNX-CH-207/208 Isolation: Genuinely separate child processes, same-UID concurrent sessions, and dead instance reaping', async () => {
  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-root-'));
  const shmDir = path.join(testRoot, 'shm');
  const sandboxDir = path.join(testRoot, 'sandbox');
  fs.mkdirSync(shmDir);
  fs.mkdirSync(sandboxDir);

  // Spawn two genuinely distinct live child processes
  const child1 = spawn('node', ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
  const child2 = spawn('node', ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });

  const inst1Id = 'inst_live1';
  const inst2Id = 'inst_live2';
  const deadInstId = 'inst_dead3';

  const sess1Id = 'sess_live1';
  const sess2Id = 'sess_live2';
  const deadSessId = 'sess_dead3';

  try {
    const pid1 = child1.pid;
    const pid2 = child2.pid;
    const deadPid = 999999;

    assert.notEqual(pid1, pid2, 'Live instances must have genuinely different PIDs');
    const start1 = getProcStartTime('/proc', pid1);
    const start2 = getProcStartTime('/proc', pid2);
    const bootId = getBootId();

    const instMetaDir = path.join(sandboxDir, '.instances');
    fs.mkdirSync(instMetaDir, { recursive: true });

    fs.writeFileSync(path.join(instMetaDir, `${inst1Id}.json`), JSON.stringify({ instanceId: inst1Id, pid: pid1, startTime: start1, bootId }));
    fs.writeFileSync(path.join(instMetaDir, `${inst2Id}.json`), JSON.stringify({ instanceId: inst2Id, pid: pid2, startTime: start2, bootId }));
    fs.writeFileSync(path.join(instMetaDir, `${deadInstId}.json`), JSON.stringify({ instanceId: deadInstId, pid: deadPid, startTime: '12345', bootId }));

    const dir1 = path.join(sandboxDir, inst1Id, sess1Id);
    const dir2 = path.join(sandboxDir, inst2Id, sess2Id);
    const dirDead = path.join(sandboxDir, deadInstId, deadSessId);
    fs.mkdirSync(dir1, { recursive: true });
    fs.mkdirSync(dir2, { recursive: true });
    fs.mkdirSync(dirDead, { recursive: true });

    const shm1 = path.join(shmDir, `tws_${inst1Id}_${sess1Id}_telemetry`);
    const shm2 = path.join(shmDir, `tws_${inst2Id}_${sess2Id}_telemetry`);
    const shmDead = path.join(shmDir, `tws_${deadInstId}_${deadSessId}_telemetry`);
    fs.writeFileSync(shm1, 'LIVE_1');
    fs.writeFileSync(shm2, 'LIVE_2');
    fs.writeFileSync(shmDead, 'DEAD');

    // Verify liveness detection
    assert.equal(isProcessAliveWithStartTime(pid1, start1, bootId), true, 'Instance 1 must be detected LIVE');
    assert.equal(isProcessAliveWithStartTime(pid2, start2, bootId), true, 'Instance 2 must be detected LIVE');
    assert.equal(isProcessAliveWithStartTime(deadPid, '12345', bootId), false, 'Instance 3 must be detected DEAD');

    // Run reconciliation from Instance 1
    reconcileDeadInstances({ sandboxDir, shmDir, currentInstanceId: inst1Id });

    // Assertions
    assert.equal(fs.existsSync(shmDead), false, 'Dead instance SHM file must be unlinked');
    assert.equal(fs.existsSync(dirDead), false, 'Dead instance workspace must be removed');
    assert.equal(fs.existsSync(path.join(instMetaDir, `${deadInstId}.json`)), false, 'Dead instance descriptor must be removed');

    assert.equal(fs.existsSync(shm1), true, 'Live Instance 1 SHM must be PRESERVED');
    assert.equal(fs.existsSync(dir1), true, 'Live Instance 1 workspace must be PRESERVED');
    assert.equal(fs.existsSync(shm2), true, 'Live Instance 2 SHM must be PRESERVED');
    assert.equal(fs.existsSync(dir2), true, 'Live Instance 2 workspace must be PRESERVED');

    // Session 1 teardown under same UID
    cleanupShmOfSession(shmDir, inst1Id, sess1Id);
    assert.equal(fs.existsSync(shm1), false, 'Session 1 SHM must be unlinked');
    assert.equal(fs.existsSync(shm2), true, 'Session 2 SHM MUST REMAIN INTACT');
  } finally {
    child1.kill();
    child2.kill();
    try { fs.rmSync(testRoot, { recursive: true, force: true }); } catch {}
  }
});

test('LNX-CH-207/208 Isolation: Escaped setsid() daemons are scoped and terminated without broad UID slaughter', async () => {
  const testHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-home-'));
  const testInst = 'inst_setsid_test';
  const testSess = 'sess_setsid_test';

  // Spawn an escaped setsid daemon that runs in background
  const script = `
import os, time
os.setsid()
time.sleep(100)
`;
  const daemon = spawn('python3', ['-c', script], {
    cwd: testHome,
    env: {
      ...process.env,
      TWS_INSTANCE_ID: testInst,
      TWS_SESSION_ID: testSess,
    },
    stdio: 'ignore',
  });

  const daemonPid = daemon.pid;
  assert.ok(daemonPid > 1);

  try {
    // Wait for daemon to call setsid
    await new Promise((r) => setTimeout(r, 200));

    // Verify daemon is running
    assert.equal(process.kill(daemonPid, 0), true, 'Daemon must be running');

    // Terminate session processes
    killSessionProcesses('/proc', {
      instanceId: testInst,
      sessionId: testSess,
      home: testHome,
    });

    // Verify daemon is terminated
    let isDead = false;
    for (let i = 0; i < 10; i++) {
      try {
        process.kill(daemonPid, 0);
        await new Promise((r) => setTimeout(r, 50));
      } catch {
        isDead = true;
        break;
      }
    }
    assert.equal(isDead, true, 'Escaped setsid daemon must be terminated by session-scoped cleanup');
  } finally {
    try { process.kill(daemonPid, 'SIGKILL'); } catch {}
    try { fs.rmSync(testHome, { recursive: true, force: true }); } catch {}
  }
});

test('LNX-CH-207/208 Isolation: Stale pidfiles and innocent processes are never killed on PID identity mismatch', async () => {
  const testHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-pidmismatch-'));
  const testInst = 'inst_pid_test';
  const testSess = 'sess_pid_test';

  // Spawn an innocent child process with different environment
  const innocent = spawn('node', ['-e', 'setInterval(() => {}, 1000)'], {
    cwd: os.tmpdir(),
    env: { ...process.env, TWS_INSTANCE_ID: 'inst_other', TWS_SESSION_ID: 'sess_other' },
    stdio: 'ignore',
  });
  const innocentPid = innocent.pid;

  try {
    // Create a stale pidfile pointing to the innocent process
    const pidFile = path.join(testHome, 'service.pid');
    fs.writeFileSync(pidFile, String(innocentPid));

    // Execute session cleanup for testSess
    killSessionProcesses('/proc', {
      instanceId: testInst,
      sessionId: testSess,
      home: testHome,
      trackedPids: [innocentPid],
    });

    // The innocent process MUST NOT be killed because environment markers and CWD do not match
    let stillAlive = false;
    try {
      stillAlive = process.kill(innocentPid, 0);
    } catch {}
    assert.equal(stillAlive, true, 'Innocent process must not be killed on PID identity mismatch');
  } finally {
    innocent.kill();
    try { fs.rmSync(testHome, { recursive: true, force: true }); } catch {}
  }
});

test('LNX-CH-207/208 Isolation: Interrupted reaping recovers safely without deleting live resources', async () => {
  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-reaping-'));
  const shmDir = path.join(testRoot, 'shm');
  const sandboxDir = path.join(testRoot, 'sandbox');
  fs.mkdirSync(shmDir);
  fs.mkdirSync(sandboxDir);

  const instMetaDir = path.join(sandboxDir, '.instances');
  fs.mkdirSync(instMetaDir, { recursive: true });

  const deadInstId = 'inst_crashed_mid_reap';
  const deadShm = path.join(shmDir, `tws_${deadInstId}_sess1_telemetry`);
  fs.writeFileSync(deadShm, 'ORPHAN');

  const reapingFile = path.join(instMetaDir, `${deadInstId}.reaping`);
  fs.writeFileSync(reapingFile, JSON.stringify({
    deadInstanceId: deadInstId,
    reaperPid: 888888, // Non-existent reaper
    reaperStartTime: '000000',
  }));

  reconcileDeadInstances({ sandboxDir, shmDir, currentInstanceId: 'inst_active_now' });

  assert.equal(fs.existsSync(deadShm), false, 'Interrupted orphan SHM must be reclaimed');
  assert.equal(fs.existsSync(reapingFile), false, 'Stale .reaping marker must be cleaned');

  try { fs.rmSync(testRoot, { recursive: true, force: true }); } catch {}
});

test('LNX-CH-207/208 Isolation: Local mode without LAB_UID (uid === undefined) cleans daemons and SHM objects cleanly', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const runtime = createLocalProcessRuntime({ cfg: {}, sandbox, bootstrap: 'bash' });

  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-localmode-'));
  const shmDir = path.join(testRoot, 'shm');
  fs.mkdirSync(shmDir);

  const testInst = 'inst_local_test';
  const testSess = 'sess_local_test';
  const shmFile = path.join(shmDir, `tws_${testInst}_${testSess}_telemetry`);
  fs.writeFileSync(shmFile, 'LOCAL_DATA');

  const homeDir = path.join(testRoot, testInst, testSess);
  fs.mkdirSync(homeDir, { recursive: true });

  // Spawn a dummy process matching the session
  const proc = spawn('node', ['-e', 'setInterval(() => {}, 1000)'], {
    cwd: homeDir,
    env: { ...process.env, TWS_INSTANCE_ID: testInst, TWS_SESSION_ID: testSess },
    stdio: 'ignore',
  });
  const procPid = proc.pid;

  try {
    assert.equal(fs.existsSync(shmFile), true);
    assert.equal(process.kill(procPid, 0), true);

    // Call cleanupSession with uid: undefined
    runtime.cleanupSession({
      shell: null,
      pid: procPid,
      uid: undefined,
      home: homeDir,
      historyFile: null,
      shmDir,
      sessionId: testSess,
      instanceId: testInst,
    });

    assert.equal(fs.existsSync(shmFile), false, 'SHM file must be cleaned in local mode');
    let isDead = false;
    for (let i = 0; i < 10; i++) {
      try {
        process.kill(procPid, 0);
        await new Promise((r) => setTimeout(r, 50));
      } catch {
        isDead = true;
        break;
      }
    }
    assert.equal(isDead, true, 'Process must be terminated in local mode');
  } finally {
    try { proc.kill(); } catch {}
    try { fs.rmSync(testRoot, { recursive: true, force: true }); } catch {}
  }
});

test('LNX-CH-207/208 Isolation: Reaper concurrency matrix: missing owner, corrupt owner, live owner, dead owner, and concurrent reapers', async () => {
  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-reaper-matrix-'));
  const sandboxDir = path.join(testRoot, 'sandbox');
  fs.mkdirSync(sandboxDir);

  const instMetaDir = path.join(sandboxDir, '.instances');
  fs.mkdirSync(instMetaDir, { recursive: true });

  const reaperLockDir = path.join(sandboxDir, '.reaper.lock');

  // Case 1: Missing owner.json -> lock preserved, not stolen
  fs.mkdirSync(reaperLockDir);
  reconcileDeadInstances({ sandboxDir, shmDir: '/dev/shm', currentInstanceId: 'inst_comp1' });
  assert.equal(fs.existsSync(reaperLockDir), true, 'Case 1: Missing owner.json must PRESERVE lock');
  fs.rmSync(reaperLockDir, { recursive: true, force: true });

  // Case 2: Corrupt owner.json -> lock preserved, not stolen
  fs.mkdirSync(reaperLockDir);
  fs.writeFileSync(path.join(reaperLockDir, 'owner.json'), 'INVALID_JSON_CORRUPT');
  reconcileDeadInstances({ sandboxDir, shmDir: '/dev/shm', currentInstanceId: 'inst_comp2' });
  assert.equal(fs.existsSync(reaperLockDir), true, 'Case 2: Corrupt owner.json must PRESERVE lock');
  fs.rmSync(reaperLockDir, { recursive: true, force: true });

  // Case 3: Live owner process -> lock preserved, not stolen
  const liveChild = spawn('node', ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
  try {
    fs.mkdirSync(reaperLockDir);
    fs.writeFileSync(path.join(reaperLockDir, 'owner.json'), JSON.stringify({
      reaperInstanceId: 'inst_live_owner',
      pid: liveChild.pid,
      startTime: getProcStartTime('/proc', liveChild.pid),
      bootId: getBootId(),
    }));
    reconcileDeadInstances({ sandboxDir, shmDir: '/dev/shm', currentInstanceId: 'inst_comp3' });
    assert.equal(fs.existsSync(reaperLockDir), true, 'Case 3: Live owner process must PRESERVE lock');
    fs.rmSync(reaperLockDir, { recursive: true, force: true });
  } finally {
    liveChild.kill();
  }

  // Case 4: Definitively dead owner process -> lock is safely recovered
  fs.mkdirSync(reaperLockDir);
  fs.writeFileSync(path.join(reaperLockDir, 'owner.json'), JSON.stringify({
    reaperInstanceId: 'inst_dead_owner',
    pid: 999998,
    startTime: '000000',
    bootId: getBootId(),
  }));
  reconcileDeadInstances({ sandboxDir, shmDir: '/dev/shm', currentInstanceId: 'inst_reclaim' });
  // The dead lock was claimed and freed upon exit
  assert.equal(fs.existsSync(reaperLockDir), false, 'Case 4: Stale dead lock was reclaimed and released cleanly');

  // Case 5: Two genuinely separate child processes competing simultaneously
  const procA = spawn('node', ['-e', `
    const { reconcileDeadInstances } = require('./src/runtime');
    for (let i = 0; i < 5; i++) {
      reconcileDeadInstances({ sandboxDir: ${JSON.stringify(sandboxDir)}, shmDir: '/dev/shm', currentInstanceId: 'inst_procA' });
    }
  `], { stdio: 'ignore' });

  const procB = spawn('node', ['-e', `
    const { reconcileDeadInstances } = require('./src/runtime');
    for (let i = 0; i < 5; i++) {
      reconcileDeadInstances({ sandboxDir: ${JSON.stringify(sandboxDir)}, shmDir: '/dev/shm', currentInstanceId: 'inst_procB' });
    }
  `], { stdio: 'ignore' });

  await Promise.all([
    new Promise((resolve) => procA.on('exit', resolve)),
    new Promise((resolve) => procB.on('exit', resolve)),
  ]);

  try { fs.rmSync(testRoot, { recursive: true, force: true }); } catch {}
});

test('LNX-CH-207/208 Isolation: Multi-instance workspace isolation: two independent server processes sharing sandbox root cannot collide', async () => {
  const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-test-multi-instance-'));
  const sandboxDir = path.join(testRoot, 'sandbox');
  fs.mkdirSync(sandboxDir);
  fs.chmodSync(sandboxDir, 0o711);

  const { createApp } = require('../../src/server');

  // Start two independent server instances sharing the exact same sandboxDir
  const inst1Id = 'inst_srv_alpha';
  const inst2Id = 'inst_srv_beta';

  const app1 = createApp({ sandboxDir, instanceId: inst1Id });
  const app2 = createApp({ sandboxDir, instanceId: inst2Id });

  try {
    const token1 = app1.store.mint({ track: 't1', lab: 'l1' });
    const token2 = app2.store.mint({ track: 't2', lab: 'l2' });

    const home1 = app1.homeOf(token1);
    const home2 = app2.homeOf(token2);

    // 1. Verify instance-scoped workspace paths
    assert.ok(home1.includes(inst1Id), 'home1 must be inside inst1Id');
    assert.ok(home2.includes(inst2Id), 'home2 must be inside inst2Id');
    assert.notEqual(path.dirname(home1), path.dirname(home2), 'Instances must have separate parent directories');

    // 2. Prepare homes with mock unprivileged UIDs (only if root)
    const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
    const uid1 = isRoot ? 10001 : undefined;
    const uid2 = isRoot ? 10002 : undefined;
    app1.sandbox.prepareHome(home1, uid1);
    app2.sandbox.prepareHome(home2, uid2);

    // Verify parent permissions are traversable (0711)
    const stat1 = fs.statSync(path.dirname(home1));
    const stat2 = fs.statSync(path.dirname(home2));
    assert.equal((stat1.mode & 0o777), 0o711, 'Instance 1 directory must be 0711 (traversable)');
    assert.equal((stat2.mode & 0o777), 0o711, 'Instance 2 directory must be 0711 (traversable)');

    // 3. Write data into each workspace
    fs.writeFileSync(path.join(home1, 'secret_alpha.txt'), 'ALPHA_DATA');
    fs.writeFileSync(path.join(home2, 'secret_beta.txt'), 'BETA_DATA');

    // 4. Verify command logging history compat
    const hist1 = path.join(path.dirname(home1), `.${token1.slice(0, 8)}.history`);
    app1.sandbox.prepareHistory(hist1, uid1);
    fs.appendFileSync(hist1, 'command_alpha\n');

    const compatHist = path.join(sandboxDir, `.${token1.slice(0, 8)}.history`);
    assert.equal(fs.existsSync(compatHist), true, 'History compat link must exist in sandbox root');
    assert.equal(fs.readFileSync(compatHist, 'utf8'), 'command_alpha\n');

    // 5. Cleanup of Instance 1 must NOT delete Instance 2 workspace
    app1.server.close();
    await new Promise((r) => setTimeout(r, 100));

    assert.equal(fs.existsSync(path.join(home2, 'secret_beta.txt')), true, 'Instance 2 data MUST survive Instance 1 shutdown');
    assert.equal(fs.existsSync(path.dirname(home2)), true, 'Instance 2 workspace MUST survive Instance 1 shutdown');
  } finally {
    try { app1.server.close(); } catch {}
    try { app2.server.close(); } catch {}
    try { fs.rmSync(testRoot, { recursive: true, force: true }); } catch {}
  }
});
