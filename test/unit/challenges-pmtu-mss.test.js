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
const CH_DIR = path.join(CHALLENGES_ROOT, 'linux', 'pmtu-mss-clamping');
const STEPS = [
  'analyze-packet-capture',
  'calculate-mss-clamping',
  'configure-mss-clamping',
  'verify-transfer-recovery',
];

function runScript(cwd, scriptPath, args = [], env = {}) {
  if (!Array.isArray(args)) {
    env = args;
    args = [];
  }
  const basename = path.basename(scriptPath);
  const isPython = basename === 'verify-transfer' || basename === 'packet-analyzer';
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

test('LNX-CH-204 loads and validates in registry', () => {
  const loader = createChallengeLoader({ challengesDir: CHALLENGES_ROOT });
  const ch = loader.getChallenge('linux', 'pmtu-mss-clamping');
  assert.ok(ch, 'pmtu-mss-clamping must be loadable');
  assert.equal(ch.id, 'LNX-CH-204');
  assert.equal(ch.level, 'advanced');
  assert.equal(ch.title, 'Path MTU Discovery Black Holes & TCP MSS Clamping Forensics');
  assert.equal(ch.tasksCount, 4);
  assert.equal(ch.steps.length, 5);
});

test('LNX-CH-204: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  assert.ok(CHALLENGE_SKILLS['pmtu-mss-clamping'], 'Skills taxonomy must be registered for pmtu-mss-clamping');
  assert.ok(Array.isArray(CHALLENGE_SKILLS['pmtu-mss-clamping']));
  assert.ok(CHALLENGE_SKILLS['pmtu-mss-clamping'].length >= 3);
});

test('LNX-CH-204: initial checks fail after setup and pass after solution', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-204-flow-'));

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
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-204: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });

  for (const step of STEPS) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch-204-skip-${step}-`));
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
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  }
});

test('LNX-CH-204: binary PCAP artifact integrity and packet header format', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-204-pcap-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const pcapFile = path.join(tmpHome, 'pmtu-incident', 'traces', 'gateway-hang.pcap');
    assert.ok(fs.existsSync(pcapFile));
    const buf = fs.readFileSync(pcapFile);
    assert.ok(buf.length > 24, 'PCAP must have global header and packets');

    // Check PCAP magic (0xa1b2c3d4 in little-endian = d4 c3 b2 a1)
    const magic = buf.readUInt32LE(0);
    assert.equal(magic, 0xa1b2c3d4, 'Valid PCAP magic header');

    // Major / Minor version: 2.4
    const vMaj = buf.readUInt16LE(4);
    const vMin = buf.readUInt16LE(6);
    assert.equal(vMaj, 2);
    assert.equal(vMin, 4);

    // Linktype: 1 (Ethernet)
    const linkType = buf.readUInt32LE(20);
    assert.equal(linkType, 1);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-204: calculation consistency between tunnel MTU and MSS clamping', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch-204-calc-'));

  try {
    const s = sandbox.runChallengeSetup(CH_DIR, tmpHome, undefined, {}, { isolateOutput: true });
    assert.equal(s.code, 0);

    const envFile = path.join(tmpHome, 'pmtu-incident', 'config', 'gateway.env');
    const content = fs.readFileSync(envFile, 'utf8');
    const m = content.match(/TUNNEL_MTU=([0-9]+)/);
    assert.ok(m, 'TUNNEL_MTU must be defined');
    const mtu = parseInt(m[1], 10);
    assert.equal(mtu, 1420);

    const ipHdr = 20;
    const tcpHdr = 20;
    const expectedMss = mtu - ipHdr - tcpHdr;
    assert.equal(expectedMss, 1380);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});
