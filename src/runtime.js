// Pluggable execution runtime interface for TWS Labs.
// Provides a unified contract for session preparation, terminal spawning,
// check grading, and lifecycle cleanup across execution backends (local process,
// isolated container, or Kubernetes pod).
const fs = require('fs');
const path = require('path');
const pty = require('node-pty');
const { killProcessSession, killProcessesOfUid, killSessionProcesses } = require('./lib');

function getProcStartTime(procDir = '/proc', pid) {
  try {
    const stat = fs.readFileSync(path.join(procDir, String(pid), 'stat'), 'utf8');
    const rparen = stat.lastIndexOf(')');
    return stat.slice(rparen + 2).split(' ')[19];
  } catch { return null; }
}

function getBootId() {
  try {
    return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim();
  } catch { return null; }
}

function isProcessAliveWithStartTime(pid, expectedStartTime, expectedBootId, procDir = '/proc') {
  if (!pid || pid <= 1) return false;
  if (expectedBootId) {
    const currentBootId = getBootId();
    if (currentBootId && currentBootId !== expectedBootId) return false;
  }
  const currentStart = getProcStartTime(procDir, pid);
  if (!currentStart) return false;
  return expectedStartTime ? currentStart === String(expectedStartTime) : true;
}

function cleanupShmOfSession(shmDir = '/dev/shm', instanceId, sessionId, uid) {
  if (!sessionId) {
    if (uid !== undefined && uid !== null) {
      cleanupShmOfUid(shmDir, uid);
    }
    return;
  }

  const prefixes = [];
  if (instanceId) {
    prefixes.push(`tws_${instanceId}_${sessionId}_`);
  }
  prefixes.push(`tws_${sessionId}_`);

  let entries;
  try { entries = fs.readdirSync(shmDir); } catch { return; }

  for (const entry of entries) {
    const matchesPrefix = prefixes.some((p) => entry.startsWith(p));
    if (!matchesPrefix) continue;
    const fullPath = path.join(shmDir, entry);
    try {
      const st = fs.lstatSync(fullPath);
      if (!st.isDirectory()) {
        if (uid === undefined || st.uid === uid) {
          fs.unlinkSync(fullPath);
        }
      }
    } catch {}
  }
}

function cleanupShmOfUid(shmDir = '/dev/shm', uid) {
  if (uid === undefined || uid === null) return;
  const targetPrefix = `tws_${uid}_`;
  let entries;
  try {
    entries = fs.readdirSync(shmDir);
  } catch {
    return;
  }
  for (const entry of entries) {
    if (!entry.startsWith(targetPrefix)) continue;
    const fullPath = path.join(shmDir, entry);
    try {
      const st = fs.lstatSync(fullPath);
      if (!st.isDirectory() && st.uid === uid) {
        fs.unlinkSync(fullPath);
      }
    } catch {
      // Idempotent: file might have already been unlinked or closed
    }
  }
}

function reapDeadInstance(deadInstanceId, sandboxDir, shmDir = '/dev/shm') {
  if (!deadInstanceId || !/^inst_[a-zA-Z0-9_-]+$/.test(deadInstanceId)) return;
  try {
    const prefix = `tws_${deadInstanceId}_`;
    for (const e of fs.readdirSync(shmDir)) {
      if (e.startsWith(prefix)) {
        try {
          const fp = path.join(shmDir, e);
          if (!fs.lstatSync(fp).isDirectory()) fs.unlinkSync(fp);
        } catch {}
      }
    }
  } catch {}

  try {
    const instDir = path.join(sandboxDir, deadInstanceId);
    if (fs.existsSync(instDir)) {
      fs.rmSync(instDir, { recursive: true, force: true });
    }
  } catch {}

  try {
    killSessionProcesses('/proc', { instanceId: deadInstanceId });
  } catch {}
}

function reconcileDeadInstances({ sandboxDir, shmDir = '/dev/shm', currentInstanceId, procDir = '/proc' }) {
  if (!sandboxDir) return;
  const instancesDir = path.join(sandboxDir, '.instances');
  if (!fs.existsSync(instancesDir)) return;

  const reaperLockDir = path.join(sandboxDir, '.reaper.lock');
  let acquired = false;
  try {
    fs.mkdirSync(reaperLockDir);
    acquired = true;
  } catch (e) {
    if (e.code === 'EEXIST') {
      let ownerProvenDead = false;
      try {
        const ownerPath = path.join(reaperLockDir, 'owner.json');
        if (fs.existsSync(ownerPath)) {
          const owner = JSON.parse(fs.readFileSync(ownerPath, 'utf8'));
          if (owner && owner.pid && owner.startTime) {
            const isAlive = isProcessAliveWithStartTime(owner.pid, owner.startTime, owner.bootId, procDir);
            if (!isAlive) {
              ownerProvenDead = true;
            }
          }
        }
      } catch {
        // Missing, unreadable, or corrupt owner metadata: ownership is uncertain.
        // Invariant: Uncertain ownership must result in preservation, never deletion.
      }
      if (ownerProvenDead) {
        try {
          fs.rmSync(reaperLockDir, { recursive: true, force: true });
          fs.mkdirSync(reaperLockDir);
          acquired = true;
        } catch {}
      }
    }
  }

  if (!acquired) return;

  try {
    try {
      fs.writeFileSync(path.join(reaperLockDir, 'owner.json'), JSON.stringify({
        reaperInstanceId: currentInstanceId,
        pid: process.pid,
        startTime: getProcStartTime(procDir, process.pid),
        bootId: getBootId(),
        time: Date.now(),
      }));
    } catch {}

    let files;
    try { files = fs.readdirSync(instancesDir); } catch { files = []; }

    for (const file of files) {
      if (file.endsWith('.reaping')) {
        const reapingFile = path.join(instancesDir, file);
        let data = null;
        try { data = JSON.parse(fs.readFileSync(reapingFile, 'utf8')); } catch {}
        if (data && data.deadInstanceId) {
          const reaperAlive = isProcessAliveWithStartTime(data.reaperPid, data.reaperStartTime, null, procDir);
          if (!reaperAlive) {
            reapDeadInstance(data.deadInstanceId, sandboxDir, shmDir);
            try { fs.rmSync(reapingFile, { force: true }); } catch {}
          }
        }
        continue;
      }

      if (!file.endsWith('.json')) continue;
      const instId = file.replace(/\.json$/, '');
      if (instId === currentInstanceId) continue;

      const metaFile = path.join(instancesDir, file);
      let meta = null;
      try { meta = JSON.parse(fs.readFileSync(metaFile, 'utf8')); } catch {}
      if (!meta) continue;

      const isAlive = isProcessAliveWithStartTime(meta.pid, meta.startTime, meta.bootId, procDir);
      if (!isAlive) {
        const reapingFile = path.join(instancesDir, `${instId}.reaping`);
        try {
          fs.renameSync(metaFile, reapingFile);
        } catch { continue; }

        try {
          fs.writeFileSync(reapingFile, JSON.stringify({
            deadInstanceId: instId,
            reaperPid: process.pid,
            reaperStartTime: getProcStartTime(procDir, process.pid),
          }));
        } catch {}

        reapDeadInstance(instId, sandboxDir, shmDir);
        try { fs.rmSync(reapingFile, { force: true }); } catch {}
      }
    }
  } finally {
    try { fs.rmSync(reaperLockDir, { recursive: true, force: true }); } catch {}
  }
}

function createLocalProcessRuntime({ cfg, sandbox, bootstrap }) {
  return {
    name: 'local-process',
    // Execution security invariant: single-host Linux DAC / UID dropping is NOT
    // per-session namespace/container isolation. Do not claim isolation.
    isIsolated: false,
    provider: 'local-process-sandbox',

    verifyIsolation() {
      // Single-host DAC UID separation does not provide per-session container/namespace isolation.
      return false;
    },

    prepareHome(home, uid) {
      return sandbox.prepareHome(home, uid);
    },

    prepareHistory(historyFile, uid) {
      return sandbox.prepareHistory(historyFile, uid);
    },

    removeTree(p) {
      return sandbox.removeTree(p);
    },

    runSetup(dir, home, uid, extraEnv = {}, opts = {}) {
      return sandbox.runSetup(dir, home, uid, extraEnv, opts);
    },

    runChallengeSetup(dir, home, uid, extraEnv = {}, opts = {}) {
      if (typeof sandbox.runChallengeSetup === 'function') {
        return sandbox.runChallengeSetup(dir, home, uid, extraEnv, opts);
      }
      return sandbox.runSetup(dir, home, uid, extraEnv, opts);
    },

    runScript(scriptPath, opts) {
      return sandbox.runScript(scriptPath, opts);
    },

    runCheck(checkFile, opts) {
      return sandbox.runCheck(checkFile, opts);
    },

    spawnTerminal({ uid, home, historyFile, extraEnv = {}, bootstrapCmd, cols = 80, rows = 24 }) {
      const cmd = bootstrapCmd || bootstrap;
      const [file, args] = sandbox.asUser(uid, home, 'bash', ['-c', cmd]);
      return pty.spawn(file, args, {
        name: 'xterm-256color',
        cols: Math.max(10, Math.min(300, cols)),
        rows: Math.max(5, Math.min(100, rows)),
        cwd: home,
        env: {
          PATH: process.env.PATH,
          HOME: home,
          TERM: 'xterm-256color',
          LANG: 'C.UTF-8',
          GIT_TERMINAL_PROMPT: '0',
          LAB_HISTORY: historyFile,
          ...extraEnv,
        },
      });
    },

    cleanupSession({ shell, pid, uid, home, historyFile, shmDir = '/dev/shm', sessionId, instanceId, trackedPids }) {
      // 1. Scoped process termination (kills shell group, tracked daemons, and exact-environ descendants; never kills server or other sessions)
      killSessionProcesses('/proc', { shellPid: pid, sessionId, instanceId, home, uid, trackedPids });
      if (shell) {
        try { shell.kill(); } catch { /* already exited */ }
      }
      // 2. Instance and session scoped SHM cleanup (never wipes other sessions' or instances' objects)
      cleanupShmOfSession(shmDir, instanceId, sessionId, uid);
      if (home) {
        sandbox.removeTree(home);
      }
      if (historyFile) {
        sandbox.removeTree(historyFile);
      }
    },
  };
}

function createExecutionRuntime(cfg, { sandbox, bootstrap }) {
  const provider = (cfg.executionRuntime || process.env.EXECUTION_RUNTIME || 'local').toLowerCase();

  switch (provider) {
    case 'local':
    case 'process':
      return createLocalProcessRuntime({ cfg, sandbox, bootstrap });

    // Future container / Kubernetes runtime plug points:
    case 'kubernetes':
    case 'k8s':
      throw new Error('Kubernetes execution runtime is not yet enabled. Fail-closed: configure EXECUTION_RUNTIME=local');

    case 'container':
    case 'docker':
      throw new Error('Per-session isolated container runtime is not yet enabled. Fail-closed: configure EXECUTION_RUNTIME=local');

    default:
      throw new Error(`Unknown EXECUTION_RUNTIME "${provider}". Supported runtimes: local`);
  }
}

/**
 * Interface validation check for isolated execution backends.
 *
 * WHAT THIS PROVES:
 * - This function verifies ONLY in-process interface compliance and runtime self-attestation.
 * - It confirms that the runtime object implements the isolated execution contract and
 *   returns true from its verifyIsolation() hook.
 *
 * WHAT THIS DOES NOT PROVE:
 * - A self-reported `isIsolated: true` or mock `verifyIsolation()` function is an interface
 *   check, NOT proof that an actual operating system security boundary exists.
 * - Actual execution isolation requires an independently enforced kernel boundary (e.g.,
 *   Kata microVMs, gVisor sandboxes, or isolated Kubernetes Pod sandboxes with strict seccomp,
 *   network namespace isolation, and dedicated cgroups).
 * - Under no circumstances should UID separation or in-memory flags be treated as container isolation.
 */
function hasVerifiedIsolation(runtime) {
  if (!runtime || typeof runtime !== 'object') return false;
  if (runtime.isIsolated !== true) return false;
  if (typeof runtime.verifyIsolation === 'function') {
    return runtime.verifyIsolation() === true;
  }
  return false;
}

module.exports = {
  createExecutionRuntime,
  createLocalProcessRuntime,
  hasVerifiedIsolation,
  cleanupShmOfUid,
  cleanupShmOfSession,
  reconcileDeadInstances,
  getProcStartTime,
  getBootId,
  isProcessAliveWithStartTime,
};
