const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { createChallengeLoader, CHALLENGE_REGISTRY } = require('../../src/challenge-loader');
const { CHALLENGE_SKILLS } = require('../../src/challenge-pages');
const { createSandbox } = require('../../src/sandbox');

const CHALLENGE_DIR = path.join(__dirname, '..', '..', 'challenges', 'linux', 'advanced', 'segfault-coredump-elf-forensics');

test('LNX-CH-209 loads and validates in registry', () => {
  const loader = createChallengeLoader();
  const c = loader.getChallenge('linux', 'segfault-coredump-elf-forensics');
  assert.ok(c, 'Challenge LNX-CH-209 not found');
  assert.equal(c.id, 'LNX-CH-209');
  assert.equal(c.slug, 'segfault-coredump-elf-forensics');
  assert.equal(c.level, 'advanced');
  assert.equal(c.tasksCount, 4);
  assert.equal(c.steps.length, 5);
});

test('LNX-CH-209: registered skill taxonomy in CHALLENGE_SKILLS', () => {
  const skills = CHALLENGE_SKILLS['segfault-coredump-elf-forensics'];
  assert.ok(Array.isArray(skills));
  assert.ok(skills.includes('ELF Forensics'));
  assert.ok(skills.includes('Core Dumps'));
  assert.ok(skills.includes('SIGSEGV Triage'));
  assert.ok(skills.includes('Register Inspection'));
});

test('LNX-CH-209: initial checks fail after setup and pass after solution', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch209-cycle-'));

  try {
    // 1. Run initial challenge setup
    const setupRes = sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
    assert.equal(setupRes.code, 0, `Setup failed: ${setupRes.out}`);

    const tasks = [
      'triage-elf-artifacts',
      'analyze-registers-memory',
      'diagnose-root-cause',
      'remediate-and-verify',
    ];

    // 2. Each check must FAIL before its solution is applied
    for (const task of tasks) {
      const checkScript = path.join(CHALLENGE_DIR, 'checks', `${task}.sh`);
      const failRes = await sandbox.runCheck(checkScript, { home: tmpHome });
      assert.equal(failRes.pass, false, `Task check ${task} unexpectedly passed before solution!`);

      // 3. Apply solution
      const solScript = path.join(CHALLENGE_DIR, 'solutions', `${task}.sh`);
      const solRes = await sandbox.runScript(solScript, { home: tmpHome });
      assert.equal(solRes.code, 0, `Solution for ${task} failed: ${solRes.out}`);

      // 4. Check must PASS after solution
      const passRes = await sandbox.runCheck(checkScript, { home: tmpHome });
      assert.equal(passRes.pass, true, `Task check ${task} failed after solution: ${passRes.message}`);
    }
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-209: all 4 skip-ahead scripts execute idempotently and enable subsequent tasks', async () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tasks = [
    'triage-elf-artifacts',
    'analyze-registers-memory',
    'diagnose-root-cause',
    'remediate-and-verify',
  ];

  for (const targetTask of tasks) {
    const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), `tws-ch209-skip-${targetTask}-`));
    try {
      // Run base setup
      const setupRes = sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
      assert.equal(setupRes.code, 0);

      const skipScript = path.join(CHALLENGE_DIR, 'setup', `${targetTask}.sh`);
      assert.ok(fs.existsSync(skipScript), `Missing skip-ahead script: ${skipScript}`);

      // Run skip-ahead script twice to prove idempotency
      const skipRes1 = await sandbox.runScript(skipScript, { home: tmpHome });
      assert.equal(skipRes1.code, 0, `First skip run failed for ${targetTask}: ${skipRes1.out}`);

      const skipRes2 = await sandbox.runScript(skipScript, { home: tmpHome });
      assert.equal(skipRes2.code, 0, `Second skip run failed for ${targetTask}: ${skipRes2.out}`);

      // Corresponding check must pass immediately
      const checkScript = path.join(CHALLENGE_DIR, 'checks', `${targetTask}.sh`);
      const checkRes = await sandbox.runCheck(checkScript, { home: tmpHome });
      assert.equal(checkRes.pass, true, `Check ${targetTask} failed after skip-ahead setup: ${checkRes.message}`);
    } finally {
      fs.rmSync(tmpHome, { recursive: true, force: true });
    }
  }
});

test('LNX-CH-209: pure-Python coredump-analyzer parses real binary bytes from core dump', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch209-analyzer-'));

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
    const analyzer = path.join(tmpHome, 'segfault-incident', 'bin', 'coredump-analyzer');
    const coreFile = path.join(tmpHome, 'segfault-incident', 'artifacts', 'core.worker_service.12480');

    // 1. Test "info" command
    const infoRes = spawnSync(analyzer, ['info', coreFile], { encoding: 'utf8' });
    assert.equal(infoRes.status, 0);
    assert.match(infoRes.stdout, /ELF Class: ELF64/);
    assert.match(infoRes.stdout, /Data Encoding: 2LSB/);
    assert.match(infoRes.stdout, /Architecture: x86_64/);
    assert.match(infoRes.stdout, /Process Name: worker_service/);
    assert.match(infoRes.stdout, /Crashed PID: 12480/);
    assert.match(infoRes.stdout, /Terminating Signal: SIGSEGV \(11\)/);
    assert.match(infoRes.stdout, /Conventional Shell Status: 139/);

    // 2. Test "registers" command
    const regRes = spawnSync(analyzer, ['registers', coreFile], { encoding: 'utf8' });
    assert.equal(regRes.status, 0);
    assert.match(regRes.stdout, /rip: 0x000055d7a81211e4/);
    assert.match(regRes.stdout, /rax: 0x0000000000000000/);
    assert.match(regRes.stdout, /rsp: 0x00007ffc6422b310/);

    // 3. Test "siginfo" command
    const sigRes = spawnSync(analyzer, ['siginfo', coreFile], { encoding: 'utf8' });
    assert.equal(sigRes.status, 0);
    assert.match(sigRes.stdout, /Signal Number: 11 \(SIGSEGV\)/);
    assert.match(sigRes.stdout, /Signal Code: 1 \(SEGV_MAPERR\)/);
    assert.match(sigRes.stdout, /Fault Address \(si_addr\): 0x0/);

    // 4. Test "maps" command
    const mapRes = spawnSync(analyzer, ['maps', coreFile], { encoding: 'utf8' });
    assert.equal(mapRes.status, 0);
    assert.match(mapRes.stdout, /worker_service/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-209: coredump-analyzer handles truncated or malformed core files safely', () => {
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch209-badcore-'));

  try {
    const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
    const analyzer = path.join(tmpHome, 'segfault-incident', 'bin', 'coredump-analyzer');

    // 1. Truncated header (under 64 bytes)
    const truncPath = path.join(tmpHome, 'trunc.core');
    fs.writeFileSync(truncPath, Buffer.from('\x7fELF\x02\x01\x01'));
    const r1 = spawnSync(analyzer, ['info', truncPath], { encoding: 'utf8' });
    assert.equal(r1.status, 1);
    assert.match(r1.stderr, /truncated ELF header/);

    // 2. Invalid magic
    const badMagicPath = path.join(tmpHome, 'badmagic.core');
    fs.writeFileSync(badMagicPath, Buffer.alloc(128, 0x41));
    const r2 = spawnSync(analyzer, ['info', badMagicPath], { encoding: 'utf8' });
    assert.equal(r2.status, 1);
    assert.match(r2.stderr, /invalid ELF magic/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-209: elf-inspector extracts GNU Build ID from executable', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch209-buildid-'));

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
    const inspector = path.join(tmpHome, 'segfault-incident', 'bin', 'elf-inspector');
    const exeFile = path.join(tmpHome, 'segfault-incident', 'artifacts', 'worker_service');

    const res = spawnSync(inspector, [exeFile], { encoding: 'utf8' });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /GNU Build ID: b84f93a1c29e6123456789abcdef0123456789ab/);
    assert.match(res.stdout, /ET_EXEC|ET_DYN/);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

test('LNX-CH-209: worker_service is a genuinely executable ELF binary that faults with exit code 139', () => {
  const sandbox = createSandbox({ labsDir: path.join(__dirname, '..', '..', 'labs') });
  const tmpHome = fs.mkdtempSync(path.join(os.tmpdir(), 'tws-ch209-exec-'));

  try {
    sandbox.runChallengeSetup(CHALLENGE_DIR, tmpHome, undefined, {});
    const exeFile = path.join(tmpHome, 'segfault-incident', 'artifacts', 'worker_service');
    assert.ok(fs.existsSync(exeFile));

    const res = spawnSync(exeFile, [], { encoding: 'utf8' });
    assert.ok(res.signal === 'SIGSEGV' || res.status === 139, `Expected SIGSEGV or status 139, got: status=${res.status}, signal=${res.signal}`);
  } finally {
    fs.rmSync(tmpHome, { recursive: true, force: true });
  }
});

