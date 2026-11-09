const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const net = require('net');

// --- Command line tracker ----------------------------------------------------
// A browser terminal sends one WebSocket message per keystroke, so "did they run
// X" needs accumulation until Enter. Honors backspace / Ctrl-C / Ctrl-U. Arrow-key
// history recall is stripped, so this is a heuristic: prefer checks that grade
// machine state, and use the command log only for "ran this command".
const ESCAPE_SEQ = /\x1b(\[[0-9;?]*[A-Za-z~]|O[A-Za-z])/g;

function createLineTracker(maxLineLen = 512) {
  let current = '';
  return {
    feed(chunk) {
      const done = [];
      for (const ch of chunk.replace(ESCAPE_SEQ, '')) {
        if (ch === '\r' || ch === '\n') {
          if (current.trim()) done.push(current.trim());
          current = '';
        } else if (ch === '\x7f' || ch === '\b') {
          current = current.slice(0, -1);
        } else if (ch === '\x03' || ch === '\x15') {
          current = '';
        } else if (ch >= ' ') {
          if (current.length < maxLineLen) current += ch;
        }
      }
      return done;
    },
  };
}

// True if `line` invokes `cmd` as a command (at the start, or after ; & | ( ),
// as opposed to merely containing the word, e.g. `echo hostname`.
function lineRunsCommand(line, cmd) {
  return new RegExp('(^|[;&|(]\\s*)' + cmd + '(\\s|$|[;&|)])').test(line);
}

// --- /proc session walking ---------------------------------------------------
// node-pty makes the shell a session leader, so its pid is the session id and
// every process the learner starts (including background jobs) shares it.
function processesInSession(procDir, sid) {
  const matches = [];
  let entries;
  try { entries = fs.readdirSync(procDir); } catch { return matches; }
  for (const entry of entries) {
    if (!/^\d+$/.test(entry)) continue;
    try {
      const stat = fs.readFileSync(path.join(procDir, entry, 'stat'), 'utf8');
      const rparen = stat.lastIndexOf(')');
      const comm = stat.slice(stat.indexOf('(') + 1, rparen);
      const after = stat.slice(rparen + 2).split(' ');
      // after: [state, ppid, pgrp, session, ...]. A killed process stays a zombie
      // until its parent reaps it; it is already dead, so it does not count.
      if (parseInt(after[3], 10) === sid && after[0] !== 'Z') matches.push({ pid: parseInt(entry, 10), comm });
    } catch { /* exited mid-read, or unreadable */ }
  }
  return matches;
}

function sessionHasProcessNamed(procDir, sid, name) {
  return processesInSession(procDir, sid).some((p) => p.comm === name);
}

function killProcessSession(procDir, sid) {
  for (const { pid } of processesInSession(procDir, sid)) {
    if (!isProtectedPid(pid)) {
      try { process.kill(pid, 'SIGKILL'); } catch { /* already gone */ }
    }
  }
}

function parseProcEnviron(buf) {
  const env = Object.create(null);
  let start = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 0) {
      if (i > start) {
        const line = buf.toString('utf8', start, i);
        const eq = line.indexOf('=');
        if (eq !== -1) env[line.slice(0, eq)] = line.slice(eq + 1);
      }
      start = i + 1;
    }
  }
  return env;
}

function getProcStartTime(procDir = '/proc', pid = process.pid) {
  try {
    const stat = fs.readFileSync(path.join(procDir, String(pid), 'stat'), 'utf8');
    const rparen = stat.lastIndexOf(')');
    const after = stat.slice(rparen + 2).split(' ');
    return after[19];
  } catch { return null; }
}

function isProtectedPid(pid, procDir = '/proc') {
  if (!pid || pid <= 1 || pid === process.pid || pid === process.ppid) return true;
  // Guard ancestors of current process up to PID 1
  let cur = process.ppid;
  while (cur > 1) {
    if (pid === cur) return true;
    try {
      const stat = fs.readFileSync(path.join(procDir, String(cur), 'stat'), 'utf8');
      const rparen = stat.lastIndexOf(')');
      const after = stat.slice(rparen + 2).split(' ');
      const ppid = parseInt(after[1], 10);
      if (ppid <= 1 || ppid === cur) break;
      cur = ppid;
    } catch {
      break;
    }
  }
  return false;
}

function killSessionProcesses(procDir, { shellPid, sessionId, instanceId, home, uid, trackedPids = [] } = {}) {
  const targets = new Set();

  if (shellPid && !isProtectedPid(shellPid, procDir)) {
    targets.add(shellPid);
    for (const { pid } of processesInSession(procDir, shellPid)) {
      if (!isProtectedPid(pid, procDir)) targets.add(pid);
    }
  }

  if (Array.isArray(trackedPids)) {
    for (const rec of trackedPids) {
      const p = typeof rec === 'number' ? rec : (rec && rec.pid);
      if (!p || isProtectedPid(p, procDir)) continue;

      // 1. UID verification where applicable
      if (uid !== undefined) {
        try {
          if (fs.statSync(path.join(procDir, String(p))).uid !== uid) continue;
        } catch { continue; }
      }

      // 2. Start-time ticks verification against PID reuse
      if (typeof rec === 'object' && rec.startTime) {
        const curStart = getProcStartTime(procDir, p);
        if (!curStart || curStart !== String(rec.startTime)) continue;
      }

      // 3. Independent ownership evidence (harvested PID must not be trusted blindly)
      let trusted = false;
      if (home) {
        try {
          const cwd = fs.readlinkSync(path.join(procDir, String(p), 'cwd'));
          if (cwd === home || cwd.startsWith(home + '/')) trusted = true;
        } catch {}

        if (!trusted) {
          try {
            const cmd = fs.readFileSync(path.join(procDir, String(p), 'cmdline'), 'utf8');
            if (cmd.includes(home)) trusted = true;
          } catch {}
        }
      }

      if (!trusted && sessionId) {
        try {
          const envBuf = fs.readFileSync(path.join(procDir, String(p), 'environ'));
          const env = parseProcEnviron(envBuf);
          if (env['TWS_SESSION_ID'] === sessionId && (!instanceId || env['TWS_INSTANCE_ID'] === instanceId)) {
            trusted = true;
          }
        } catch {}
      }

      if (trusted) {
        targets.add(p);
      }
    }
  }

  let entries;
  try { entries = fs.readdirSync(procDir); } catch { entries = []; }
  for (const entry of entries) {
    if (!/^\d+$/.test(entry)) continue;
    const p = parseInt(entry, 10);
    if (isProtectedPid(p, procDir) || targets.has(p)) continue;

    try {
      if (uid !== undefined) {
        if (fs.statSync(path.join(procDir, entry)).uid !== uid) continue;
      }

      let hasMarker = false;
      let hasAnchor = false;

      try {
        const envBuf = fs.readFileSync(path.join(procDir, entry, 'environ'));
        const env = parseProcEnviron(envBuf);
        if (sessionId && env['TWS_SESSION_ID'] === sessionId) {
          if (!instanceId || env['TWS_INSTANCE_ID'] === instanceId) {
            hasMarker = true;
          }
        }
      } catch {}

      if (home) {
        try {
          const cwd = fs.readlinkSync(path.join(procDir, entry, 'cwd'));
          if (cwd === home || cwd.startsWith(home + '/')) hasAnchor = true;
        } catch {}

        if (!hasAnchor) {
          try {
            const cmd = fs.readFileSync(path.join(procDir, entry, 'cmdline'), 'utf8');
            if (cmd.includes(home)) hasAnchor = true;
          } catch {}
        }
      }

      // Mandatory safety: NEVER kill solely because of environment variable markers.
      // A process is targeted if:
      // 1. It carries the verified session environment marker AND workspace anchor
      // OR
      // 2. In unprivileged UID mode (where dumpable=0 under setuid/gosu prevents reading /proc/environ),
      //    it matches the session's specific UID AND its command-line or CWD anchors strictly to this session's unique home workspace.
      if ((hasMarker && hasAnchor) || (uid !== undefined && hasAnchor)) {
        targets.add(p);
      }
    } catch {}
  }

  for (const pid of targets) {
    if (isProtectedPid(pid, procDir)) continue;
    try { process.kill(pid, 'SIGKILL'); } catch {}
  }
}

// Deprecated per-UID kill helper; guarded to never kill server or parent.
function killProcessesOfUid(procDir, uid) {
  let entries;
  try { entries = fs.readdirSync(procDir); } catch { return; }
  for (const entry of entries) {
    if (!/^\d+$/.test(entry)) continue;
    const p = parseInt(entry, 10);
    if (isProtectedPid(p)) continue;
    try {
      if (fs.statSync(path.join(procDir, entry)).uid === uid) process.kill(p, 'SIGKILL');
    } catch { /* gone or not ours to signal */ }
  }
}

// --- Client address -----------------------------------------------------------
// Behind the ALB the socket peer is the load balancer. The ALB appends the address
// it saw to X-Forwarded-For, so the *rightmost* entry is the one a client cannot
// forge; anything to its left is client-supplied.
function clientIp(req, { trustProxy = true } = {}) {
  const xff = trustProxy && req.headers && req.headers['x-forwarded-for'];
  if (xff) {
    const last = String(xff).split(',').pop().trim();
    if (last && net.isIP(last)) return last;
  }
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

// --- Cgroup v2 stats -----------------------------------------------------------
// Parsing is split from file I/O so it is testable without a real filesystem.
function parseCpuStat(statText) {
  const m = statText.match(/usage_usec (\d+)/);
  return m ? parseInt(m[1], 10) : null;
}

// cpu.max is "<quota> <period>" ("50000 100000" = half a core) or "max <period>".
function parseCpuMax(text) {
  const [quota, period] = text.trim().split(/\s+/);
  if (quota === 'max') return null;
  const q = parseInt(quota, 10);
  const p = parseInt(period, 10);
  return q > 0 && p > 0 ? q / p : null;
}

function parseMemory(currentText, maxText, totalMemFallback) {
  const used = parseInt(currentText, 10);
  const maxRaw = maxText.trim();
  const max = maxRaw === 'max' ? totalMemFallback : parseInt(maxRaw, 10);
  if (Number.isNaN(used) || Number.isNaN(max)) return null;
  return { used, max };
}

const readOrNull = (fn) => { try { return fn(); } catch { return null; } };
const readCgroupCpuUsageUsec = () => readOrNull(() => parseCpuStat(fs.readFileSync('/sys/fs/cgroup/cpu.stat', 'utf8')));
const readCgroupCpuLimitCores = () => readOrNull(() => parseCpuMax(fs.readFileSync('/sys/fs/cgroup/cpu.max', 'utf8')));
const readCgroupMemory = (totalMemFallback) => readOrNull(() => parseMemory(
  fs.readFileSync('/sys/fs/cgroup/memory.current', 'utf8'), fs.readFileSync('/sys/fs/cgroup/memory.max', 'utf8'), totalMemFallback));

// --- Unprivileged uid pool -------------------------------------------------------
// One uid per live session so learners cannot see, signal or starve each other.
function createUidPool(base, size) {
  const used = new Set();
  return {
    acquire() {
      if (base === undefined) return undefined;       // not root: no privilege drop at all
      for (let i = 0; i < size; i++) if (!used.has(base + i)) { used.add(base + i); return base + i; }
      return null;                                     // exhausted (cannot happen below the seat cap)
    },
    release(uid) { if (uid !== undefined && uid !== null) used.delete(uid); },
    inUse: () => used.size,
  };
}

// --- Session store ----------------------------------------------------------------
// A factory, not module state, so every app instance (and test) is isolated.
function createSessionStore({ connectDeadlineMs, onExpire }) {
  const sessions = new Map();
  function drop(token) {
    const s = sessions.get(token);
    if (!s) return;
    clearTimeout(s.connectDeadline);
    sessions.delete(token);
    if (onExpire) onExpire(s);
  }
  return {
    mint(meta, ip = null, uid, instanceId = null) {
      const token = crypto.randomBytes(16).toString('hex');
      const sessionId = `sess_${token.slice(0, 8)}`;
      // A minted token whose WebSocket never opens (tab closed, bot) must not hold a seat.
      const connectDeadline = setTimeout(() => drop(token), connectDeadlineMs);
      connectDeadline.unref();
      sessions.set(token, {
        createdAt: Date.now(), lastActivity: Date.now(), meta, ip, uid,
        sessionId, instanceId,
        shellPid: null, shell: null, home: null, tracker: createLineTracker(), connectDeadline,
        trackedPids: [],
      });
      return token;
    },
    get: (token) => sessions.get(token),
    has: (token) => sessions.has(token),
    size: () => sessions.size,
    allSessions: () => Array.from(sessions.values()),
    // Minted-but-unconnected tokens count too: they hold a seat until their deadline.
    countByIp(ip) { let n = 0; for (const s of sessions.values()) if (s.ip === ip) n++; return n; },
    touch(token) { const s = sessions.get(token); if (s) s.lastActivity = Date.now(); },
    markConnected(token, { shellPid, home, shell = null, trackedPids = [] } = {}) {
      const s = sessions.get(token);
      if (!s) return;
      clearTimeout(s.connectDeadline);
      s.shellPid = shellPid;
      s.home = home;
      if (shell) s.shell = shell;
      if (Array.isArray(trackedPids)) s.trackedPids = trackedPids;
    },
    expire: drop,
    // Lines completed by this chunk of terminal input.
    recordInput(token, chunk) {
      const s = sessions.get(token);
      return s ? s.tracker.feed(chunk) : [];
    },
  };
}

module.exports = {
  createLineTracker, lineRunsCommand, processesInSession, sessionHasProcessNamed, killProcessSession, killProcessesOfUid,
  parseProcEnviron, isProtectedPid, getProcStartTime, killSessionProcesses, clientIp,
  parseCpuStat, parseCpuMax, parseMemory, readCgroupCpuUsageUsec, readCgroupCpuLimitCores, readCgroupMemory,
  createUidPool, createSessionStore,
};
