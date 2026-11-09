const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const fs = require('node:fs');
const http = require('node:http');
const { createApp } = require('../../src/server');
const { assertBrandedPage } = require('../assert-branded');

const BEGINNER_CHALLENGES = [
  'file-directory-permissions',
  'users-groups-access',
  'the-missing-disk',
  'mounting-filesystem-basics',
  'process-service-fundamentals',
  'archive-compression-basics',
  'shell-environment-variables',
  'text-search-grep-pipes',
  'package-management-basics',
  'cron-job-scheduling',
];

const INTERMEDIATE_CHALLENGES = [
  'broken-deployment',
  'disk-pressure',
  'process-resource',
  'systemd-troubleshooting',
  'network-outage',
  'port-socket-binding-conflict',
  'dns-resolution-troubleshooting',
  'ssh-authentication-troubleshooting',
  'file-descriptor-limit-exhaustion',
  'memory-pressure-oom-killer',
];

const ADVANCED_CHALLENGES = [
  'directory-spool-arg-max',
  'tcp-accept-queue-saturation',
  'cgroup-cfs-throttling',
  'pmtu-mss-clamping',
  'systemd-dependency-cycle',
  'zombie-process-lifecycle-reaping',
  'multi-thread-deadlock-futex',
  'posix-shm-leak-lifecycle',
  'segfault-coredump-elf-forensics',
  'linux-capabilities-privilege-boundary',
];

const CHALLENGES = [...BEGINNER_CHALLENGES, ...INTERMEDIATE_CHALLENGES, ...ADVANCED_CHALLENGES];

function startApp(opts = {}) {
  const base = process.env.SANDBOX_DIR || os.tmpdir();
  fs.mkdirSync(base, { recursive: true });
  const sandboxDir = fs.mkdtempSync(path.join(base, 'test-ch-browser-'));
  const app = createApp({
    labsDir: path.join(__dirname, '..', '..', 'labs'),
    challengesDir: path.join(__dirname, '..', '..', 'challenges'),
    sandboxDir,
    profile: 'local',
    ...opts,
  });
  return new Promise((resolve) => app.server.listen(0, '127.0.0.1', () => {
    const port = app.server.address().port;
    resolve({
      ...app,
      port,
      origin: `http://127.0.0.1:${port}`,
      stop: () => {
        try { fs.rmSync(sandboxDir, { recursive: true, force: true }); } catch {}
        return new Promise((res) => app.server.close(res));
      },
    });
  }));
}

function get(app, urlPath) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: app.port, path: urlPath }, (res) => {
      let raw = '';
      res.on('data', (c) => { raw += c; });
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: raw }));
    }).on('error', reject);
  });
}

test('GET /challenges renders the flat technology-based challenge catalogue with all 8 topics', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'text/html');
    assertBrandedPage(res.body, 'Challenges', '/challenges');

    // 1. Header / Hero section
    assert.match(res.body, /class="challenges-hero"/);
    assert.match(res.body, /class="challenges-eyebrow">Engineering Challenges<\/span>/);
    assert.match(res.body, /<h1 class="challenges-hero-title">Master technology through real incidents\.<\/h1>/);
    assert.match(res.body, /class="challenges-status-pill"[^>]*><span class="live-dot"[^>]*><\/span>30 Available<\/span>/);

    // 2. Responsive grid of technology cards (flat collection of 8 topics)
    assert.match(res.body, /class="topic-cards-grid"/);

    // Topic 1: Linux (Implemented, 30 challenges, links to /challenges/linux)
    assert.match(res.body, /href="\/challenges\/linux"/);
    assert.match(res.body, /style="--topic-accent:\s*#8a63e8;"/);
    assert.match(res.body, /<h2 class="topic-card-title">Linux<\/h2>/);
    assert.match(res.body, /<span class="topic-badge live">30 Challenges<\/span>/);
    assert.match(res.body, /Explore challenges &rarr;/);

    // Topics 2-8: Unimplemented topics (must show COMING SOON, distinct accents, and NO link)
    const comingSoonTopics = [
      { title: 'Shell Scripting', accent: '#5fd39a', slug: 'shell' },
      { title: 'Git and GitHub', accent: '#f08080', slug: 'git' },
      { title: 'Docker', accent: '#5ccfee', slug: 'docker' },
      { title: 'Kubernetes', accent: '#7aa2f7', slug: 'kubernetes' },
      { title: 'CI/CD with GitHub Actions', accent: '#c084fc', slug: 'github-actions' },
      { title: 'Networking', accent: '#2dd4bf', slug: 'networking' },
      { title: 'Terraform on AWS', accent: '#f4b860', slug: 'terraform' },
    ];

    for (const t of comingSoonTopics) {
      assert.match(res.body, new RegExp(`<h2 class="topic-card-title">${t.title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}<\\/h2>`));
      assert.match(res.body, new RegExp(`--topic-accent:\\s*${t.accent}`));
      // Must not link to empty challenge lists
      assert.equal(res.body.includes(`href="/challenges/${t.slug}"`), false, `Unimplemented topic ${t.slug} should not have a navigable link`);
    }

    // Must have exactly 7 COMING SOON badges
    const soonMatches = res.body.match(/<span class="topic-badge soon">COMING SOON<\/span>/g) || [];
    assert.equal(soonMatches.length, 7);

    // No category headings, nested containers, or cards inside cards
    assert.equal(res.body.includes('DevOps Line'), false);
    assert.equal(res.body.includes('Cloud Line'), false);
    assert.equal(res.body.includes('class="card challenge-card"'), false);
    assert.equal(res.body.includes('Start challenge &rarr;'), false);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/:domain for unimplemented topic returns 404 preventing empty list navigation', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/shell');
    assert.equal(res.status, 404);
    assertBrandedPage(res.body, 'Challenges', '/challenges/shell');
    assert.match(res.body, /Off course\./);

    const res2 = await get(app, '/challenges/docker');
    assert.equal(res2.status, 404);

    const res3 = await get(app, '/challenges/terraform');
    assert.equal(res3.status, 404);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux renders the landing page with breadcrumbs and no challenge cards', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux');
    assert.equal(res.status, 200);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux');

    // Breadcrumbs
    assert.match(res.body, /<p class="crumb"><a href="\/challenges">Challenges<\/a><i>\/<\/i><span>Linux Troubleshooting<\/span><\/p>/);

    // Hero, overview and learning path
    assert.match(res.body, /class="challenges-hero"/);
    assert.match(res.body, /Master Linux through real incidents\./);
    assert.match(res.body, /30 Available/);
    assert.match(res.body, /aria-label="Beginner: 10 Challenges"/);
    assert.match(res.body, /<span class="overview-count">10<\/span>/);
    assert.match(res.body, /aria-label="Intermediate: 10 Challenges"/);
    assert.match(res.body, /<span class="overview-count">10<\/span>/);
    assert.match(res.body, /aria-label="Advanced: 10 Challenges"/);
    assert.match(res.body, /<span class="overview-count">10<\/span>/);
    assert.match(res.body, /class="challenges-overview-row"/);
    assert.match(res.body, /Your learning path/);

    // No challenge cards on landing page
    assert.equal(res.body.includes('class="card challenge-card"'), false, 'Challenge cards must not appear on landing page');
    assert.equal(res.body.includes('Start challenge &rarr;'), false, 'Start challenge button must not appear on landing page');
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/level/beginner renders dedicated listing with exactly the 10 Beginner challenges', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux/level/beginner');
    assert.equal(res.status, 200);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux/level/beginner');

    // Breadcrumbs and back navigation
    assert.match(res.body, /<p class="crumb"><a href="\/challenges">Challenges<\/a><i>\/<\/i><a href="\/challenges\/linux">Linux Troubleshooting<\/a><i>\/<\/i><span>Beginner<\/span><\/p>/);
    assert.match(res.body, /href="\/challenges\/linux" class="challenges-back-link">&larr; Back to Learning Path<\/a>/);
    assert.match(res.body, /<h1 class="page-title">Beginner Challenges<\/h1>/);
    assert.match(res.body, /10 Challenges &middot; <span class="chip chip-live"/);

    // Exactly the 5 beginner challenges must be present with start buttons
    for (const slug of BEGINNER_CHALLENGES) {
      assert.match(res.body, new RegExp(`/challenges/linux/${slug}`));
    }
    assert.match(res.body, /LNX-CH-001/);
    assert.match(res.body, /File &amp; Directory Permissions/);
    assert.match(res.body, /LNX-CH-002/);
    assert.match(res.body, /Users, Groups &amp; Access Control/);
    assert.match(res.body, /LNX-CH-003/);
    assert.match(res.body, /The Missing Disk/);
    assert.match(res.body, /LNX-CH-004/);
    assert.match(res.body, /Mounting &amp; Filesystem Basics/);
    assert.match(res.body, /LNX-CH-005/);
    assert.match(res.body, /Process &amp; Service Fundamentals/);
    assert.match(res.body, /Start challenge &rarr;/);

    // Intermediate challenges must NOT be present
    for (const slug of INTERMEDIATE_CHALLENGES) {
      assert.equal(res.body.includes(`/challenges/linux/${slug}`), false, `Intermediate challenge ${slug} should not be in Beginner listing`);
    }
    assert.equal(res.body.includes('LNX-CH-101'), false);
    assert.equal(res.body.includes('LNX-CH-105'), false);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/level/intermediate renders dedicated listing with exactly the 10 Intermediate challenges', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux/level/intermediate');
    assert.equal(res.status, 200);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux/level/intermediate');

    // Breadcrumbs and back navigation
    assert.match(res.body, /<p class="crumb"><a href="\/challenges">Challenges<\/a><i>\/<\/i><a href="\/challenges\/linux">Linux Troubleshooting<\/a><i>\/<\/i><span>Intermediate<\/span><\/p>/);
    assert.match(res.body, /href="\/challenges\/linux" class="challenges-back-link">&larr; Back to Learning Path<\/a>/);
    assert.match(res.body, /<h1 class="page-title">Intermediate Challenges<\/h1>/);
    assert.match(res.body, /10 Challenges &middot; <span class="chip chip-live"/);

    // Exactly the 10 intermediate challenges must be present with start buttons
    for (const slug of INTERMEDIATE_CHALLENGES) {
      assert.match(res.body, new RegExp(`/challenges/linux/${slug}`));
    }
    assert.match(res.body, /LNX-CH-101/);
    assert.match(res.body, /Broken Deployment &amp; Dependency Triage/);
    assert.match(res.body, /LNX-CH-102/);
    assert.match(res.body, /Linux Disk Pressure &amp; Log Forensics/);
    assert.match(res.body, /LNX-CH-103/);
    assert.match(res.body, /Linux Process &amp; Resource Troubleshooting/);
    assert.match(res.body, /LNX-CH-104/);
    assert.match(res.body, /Linux Service Failure &amp; Systemd Troubleshooting/);
    assert.match(res.body, /LNX-CH-105/);
    assert.match(res.body, /Network Outage: The Missing Route/);
    assert.match(res.body, /LNX-CH-106/);
    assert.match(res.body, /Service Port Binding &amp; Socket Contention/);
    assert.match(res.body, /LNX-CH-107/);
    assert.match(res.body, /DNS &amp; Name Service Switch Triage/);
    assert.match(res.body, /LNX-CH-108/);
    assert.match(res.body, /SSH Key Authentication &amp; Access Hardening/);
    assert.match(res.body, /LNX-CH-109/);
    assert.match(res.body, /File Descriptor Leak &amp; Resource Limits/);
    assert.match(res.body, /LNX-CH-110/);
    assert.match(res.body, /Linux Memory Pressure &amp; OOM-Killer Forensics/);
    assert.match(res.body, /Start challenge &rarr;/);

    // Beginner challenges must NOT be present
    for (const slug of BEGINNER_CHALLENGES) {
      assert.equal(res.body.includes(`/challenges/linux/${slug}`), false, `Beginner challenge ${slug} should not be in Intermediate listing`);
    }
    assert.equal(res.body.includes('LNX-CH-001'), false);
    assert.equal(res.body.includes('LNX-CH-005'), false);
    assert.equal(res.body.includes('LNX-CH-010'), false);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/level/advanced renders dedicated listing with exactly the 10 Advanced challenges', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux/level/advanced');
    assert.equal(res.status, 200);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux/level/advanced');

    // Breadcrumbs and back navigation
    assert.match(res.body, /<p class="crumb"><a href="\/challenges">Challenges<\/a><i>\/<\/i><a href="\/challenges\/linux">Linux Troubleshooting<\/a><i>\/<\/i><span>Advanced<\/span><\/p>/);
    assert.match(res.body, /href="\/challenges\/linux" class="challenges-back-link">&larr; Back to Learning Path<\/a>/);
    assert.match(res.body, /<h1 class="page-title">Advanced Challenges<\/h1>/);
    assert.match(res.body, /10 Challenges &middot; <span class="chip chip-live"/);

    // Exactly the 10 advanced challenges must be present with start buttons
    for (const slug of ADVANCED_CHALLENGES) {
      assert.match(res.body, new RegExp(`/challenges/linux/${slug}`));
    }
    assert.match(res.body, /LNX-CH-201/);
    assert.match(res.body, /LNX-CH-202/);
    assert.match(res.body, /LNX-CH-203/);
    assert.match(res.body, /LNX-CH-204/);
    assert.match(res.body, /LNX-CH-205/);
    assert.match(res.body, /LNX-CH-206/);
    assert.match(res.body, /LNX-CH-207/);
    assert.match(res.body, /LNX-CH-208/);
    assert.match(res.body, /LNX-CH-209/);
    assert.match(res.body, /LNX-CH-210/);
    assert.match(res.body, /Start challenge &rarr;/);
    assert.match(res.body, /class="challenge-tags"/);

    // Beginner challenges must NOT be present
    for (const slug of BEGINNER_CHALLENGES) {
      assert.equal(res.body.includes(`/challenges/linux/${slug}`), false, `Beginner challenge ${slug} should not be in Advanced listing`);
    }
    assert.equal(res.body.includes('LNX-CH-001'), false);
    assert.equal(res.body.includes('LNX-CH-005'), false);
    assert.equal(res.body.includes('LNX-CH-010'), false);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/level/invalid returns 404', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux/level/invalid-tier');
    assert.equal(res.status, 404);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux/level/invalid-tier');
    assert.match(res.body, /Off course\./);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/unknown domain returns 404 with branded page', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/nonexistent-domain');
    assert.equal(res.status, 404);
    assertBrandedPage(res.body, 'Challenges', '/challenges/nonexistent-domain');
    assert.match(res.body, /Off course\./);
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/:slug renders individual challenge detail and terminal shell for all 30 challenges', async () => {
  const app = await startApp();
  try {
    for (let i = 0; i < CHALLENGES.length; i++) {
      const slug = CHALLENGES[i];
      const res = await get(app, `/challenges/linux/${slug}`);
      assert.equal(res.status, 200, `Expected 200 for /challenges/linux/${slug}`);
      assertBrandedPage(res.body, 'Challenges', `/challenges/linux/${slug}`);

      // Verify breadcrumbs
      assert.match(res.body, /<p class="crumb"><a href="\/challenges">Challenges<\/a><i>\/<\/i><a href="\/challenges\/linux">Linux Troubleshooting<\/a><i>\/<\/i><span>/);

      // Verify UI components required by terminal engine and grading
      assert.match(res.body, /id="term"/, `${slug}: terminal container`);
      assert.match(res.body, /id="status-pill"/, `${slug}: status pill`);
      assert.match(res.body, /id="lab-timer"/, `${slug}: session timer`);
      assert.match(res.body, /id="lab-timer-text"/, `${slug}: session timer text`);
      assert.match(res.body, /id="journey"/, `${slug}: journey progress`);
      assert.match(res.body, /id="jticks"/, `${slug}: journey ticks`);
      assert.match(res.body, /id="task-current"/, `${slug}: current task counter`);
      assert.match(res.body, /id="task-total"[^>]*>([1-9]\d*)<\/span>/, `${slug}: task-total must be non-zero`);
      assert.match(res.body, /id="jfill"/, `${slug}: journey fill bar`);
      assert.match(res.body, /class="step-card"/, `${slug}: step card`);
      assert.match(res.body, /id="step-counter"/, `${slug}: step counter`);
      assert.match(res.body, /id="step-hint"/, `${slug}: step hint/feedback`);
      assert.match(res.body, /id="action-btn"/, `${slug}: check/action button`);
      assert.match(res.body, /id="back-btn"/, `${slug}: back button`);
      assert.match(res.body, /id="skip-btn"/, `${slug}: skip button`);
      assert.match(res.body, /id="hint-btn"/, `${slug}: hint button`);
      assert.match(res.body, /id="restart-btn"/, `${slug}: restart button`);
      assert.match(res.body, /id="end-btn"/, `${slug}: end challenge button`);
      assert.match(res.body, /id="fs-btn"/, `${slug}: fullscreen button`);
      assert.match(res.body, /id="invite"/, `${slug}: invite form container`);
      assert.match(res.body, /id="stats-box"/, `${slug}: host stats`);

      // Verify embedded JSON configuration
      const jsonMatch = res.body.match(/<script id="lab-data" type="application\/json">(.*?)<\/script>/);
      assert.ok(jsonMatch, `${slug}: lab-data script tag present`);
      const data = JSON.parse(jsonMatch[1]);

      assert.equal(data.type, 'challenge');
      assert.equal(data.domain, 'linux');
      assert.equal(data.challenge, slug);
      assert.equal(data.trackUrl, '/challenges/linux');
      assert.ok(data.steps.length >= 4, `${slug}: at least 4 steps (1 lesson + 3 tasks)`);
      assert.equal(data.steps[0].type, 'lesson');
      assert.ok(data.steps[0].bodyHtml.length > 0, `${slug}: bodyHtml rendered from markdown`);

      // Verify task steps have hints and checks
      const tasks = data.steps.filter((s) => s.type === 'task');
      assert.ok(tasks.length >= 3, `${slug}: at least 3 tasks`);
      for (const t of tasks) {
        assert.ok(t.title && t.title.trim().length > 0);
        assert.ok(t.bodyHtml && t.bodyHtml.trim().length > 0);
      }

      // Verify next challenge pointer
      if (i < CHALLENGES.length - 1) {
        const nextSlug = CHALLENGES[i + 1];
        assert.ok(data.next, `${slug}: has next challenge pointer`);
        assert.equal(data.next.href, `/challenges/linux/${nextSlug}`);
      } else {
        assert.equal(data.next, null, `${slug}: last challenge has no next pointer`);
      }

      // Verify script dependencies loaded
      assert.match(res.body, /src="\/xterm\/xterm\.js"/);
      assert.match(res.body, /src="\/xterm\/addon-fit\.js"/);
      assert.match(res.body, /src="\/progress\.js"/);
      assert.match(res.body, /src="\/lab\.js"/);
    }
  } finally {
    await app.stop();
  }
});

test('GET /challenges/linux/invalid-slug returns 404 with branded page', async () => {
  const app = await startApp();
  try {
    const res = await get(app, '/challenges/linux/nonexistent-challenge-slug');
    assert.equal(res.status, 404);
    assertBrandedPage(res.body, 'Challenges', '/challenges/linux/nonexistent-challenge-slug');
    assert.match(res.body, /Off course\./);
  } finally {
    await app.stop();
  }
});

test('Client session lifecycle: page fetch -> lab-data payload -> session mint -> timer polling', async () => {
  const app = await startApp();
  try {
    // 1. Client loads the challenge page
    const pageRes = await get(app, '/challenges/linux/broken-deployment');
    assert.equal(pageRes.status, 200);

    const jsonMatch = pageRes.body.match(/<script id="lab-data" type="application\/json">(.*?)<\/script>/);
    assert.ok(jsonMatch);
    const data = JSON.parse(jsonMatch[1]);

    // 2. Client lab.js extracts payload and calls POST /session
    const sessionPayload = data.type === 'challenge'
      ? { type: 'challenge', domain: data.domain, challenge: data.challenge }
      : { track: data.track, lab: data.lab };

    const mintRes = await new Promise((resolve, reject) => {
      const postData = JSON.stringify(sessionPayload);
      const req = http.request({
        host: '127.0.0.1',
        port: app.port,
        path: '/session',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData),
          'Origin': app.origin,
        },
      }, (res) => {
        let raw = '';
        res.on('data', (c) => { raw += c; });
        res.on('end', () => resolve({ status: res.statusCode, json: JSON.parse(raw) }));
      });
      req.on('error', reject);
      req.write(postData);
      req.end();
    });

    assert.equal(mintRes.status, 200);
    assert.ok(mintRes.json.token);

    // 3. Client lab.js polls timer
    const timerRes = await get(app, `/session/remaining?token=${mintRes.json.token}`);
    assert.equal(timerRes.status, 200);
    const timerData = JSON.parse(timerRes.body);
    assert.ok(timerData.remainingSec > 0);
  } finally {
    await app.stop();
  }
});

test('Live status indicator CSS animation and reduced-motion styling in components.css', () => {
  const css = fs.readFileSync(path.join(__dirname, '..', '..', 'public', 'components.css'), 'utf8');

  // Chip live styling
  assert.match(css, /\.chip-live\s*\{[^}]*color:\s*var\(--ok\)/);
  assert.match(css, /\.chip-live\s*\{[^}]*text-transform:\s*uppercase/);

  // Live dot styling
  assert.match(css, /\.live-dot\s*\{[^}]*background:\s*var\(--ok\)/);
  assert.match(css, /\.live-dot\s*\{[^}]*border-radius:\s*50%/);
  assert.match(css, /\.live-dot\s*\{[^}]*animation:\s*pulse-live\s*1\.5s/);

  // Keyframes definition
  assert.match(css, /@keyframes\s+pulse-live/);

  // Reduced motion media query
  assert.match(css, /@media\s*\(\s*prefers-reduced-motion:\s*reduce\s*\)\s*\{[\s\S]*?\.live-dot\s*\{[^}]*animation:\s*none/);
});

test('challengesLandingBody dynamically computes total available challenges including all active levels', () => {
  const { challengesLandingBody } = require('../../src/challenge-pages');
  const domains = [{ id: 'linux', title: 'Linux Troubleshooting', description: 'Desc' }];

  // Mock challengeLoader with beginner (10), intermediate (5), and advanced (3)
  const mockLoader = {
    listChallenges(domain) {
      if (domain !== 'linux') return [];
      const list = [];
      for (let i = 1; i <= 10; i++) list.push({ id: `LNX-BEG-${i}`, slug: `beg-${i}`, level: 'beginner' });
      for (let i = 1; i <= 5; i++) list.push({ id: `LNX-INT-${i}`, slug: `int-${i}`, level: 'intermediate' });
      for (let i = 1; i <= 3; i++) list.push({ id: `LNX-ADV-${i}`, slug: `adv-${i}`, level: 'advanced' });
      return list;
    },
  };

  const html = challengesLandingBody(domains, mockLoader, 'linux');

  // Badge must be 18 Available (10 beginner + 5 intermediate + 3 advanced)
  assert.match(html, /class="challenges-status-pill"[^>]*><span class="live-dot"[^>]*><\/span>18 Available<\/span>/);

  // Level counts must reflect beginner (10), intermediate (5), and advanced (3)
  assert.match(html, /aria-label="Beginner: 10 Challenges"/);
  assert.match(html, /<span class="overview-count">10<\/span>/);
  assert.match(html, /aria-label="Intermediate: 5 Challenges"/);
  assert.match(html, /<span class="overview-count">5<\/span>/);
  assert.match(html, /aria-label="Advanced: 3 Challenges"/);
  assert.match(html, /<span class="overview-count">3<\/span>/);
});
