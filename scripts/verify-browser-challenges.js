const puppeteer = require('puppeteer-core');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createApp } = require('../src/server');

const ARTIFACT_SHOTS = '/home/heyyprakhar1/.gemini/antigravity-cli/brain/0f706581-dc0b-4c17-aec1-04dd8056a488/screenshots';
const LOCAL_SHOTS = path.join(__dirname, '..', 'test', 'e2e', 'screenshots');

fs.mkdirSync(ARTIFACT_SHOTS, { recursive: true });
fs.mkdirSync(LOCAL_SHOTS, { recursive: true });

async function saveScreenshots(page, name) {
  const p1 = path.join(ARTIFACT_SHOTS, `${name}.png`);
  const p2 = path.join(LOCAL_SHOTS, `${name}.png`);
  await page.screenshot({ path: p1, fullPage: true });
  fs.copyFileSync(p1, p2);
  console.log(`Saved screenshot: ${name}.png`);
}

(async () => {
  const base = process.env.SANDBOX_DIR || os.tmpdir();
  const sandboxDir = fs.mkdtempSync(path.join(base, 'test-browser-run-'));
  const app = createApp({
    labsDir: path.join(__dirname, '..', 'labs'),
    challengesDir: path.join(__dirname, '..', 'challenges'),
    sandboxDir,
    profile: 'local',
  });

  const server = await new Promise((resolve) => {
    const s = app.server.listen(0, '127.0.0.1', () => resolve(s));
  });
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;
  console.log(`Server listening on ${baseUrl}`);

  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  const page = await browser.newPage();
  const problems = [];
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console error: ${m.text()}`);
  });
  page.on('requestfailed', (r) => {
    if (!/favicon|\/ws\?|fonts\.(googleapis|gstatic)\.com/.test(r.url())) {
      problems.push(`request failed: ${r.url()}`);
    }
  });

  try {
    // -------------------------------------------------------------
    // 1. Desktop: Technology-Based Challenge Catalogue (/challenges)
    // -------------------------------------------------------------
    console.log('\n=== 1. Verifying Technology-Based Challenge Catalogue (Desktop 1440x900) ===');
    await page.setViewport({ width: 1440, height: 900 });
    await page.goto(`${baseUrl}/challenges`, { waitUntil: 'networkidle2' });

    const heroTitle = await page.$eval('.challenges-hero-title', (el) => el.textContent.trim());
    const eyebrow = await page.$eval('.challenges-eyebrow', (el) => el.textContent.trim());
    const statusPill = await page.$eval('.challenges-status-pill', (el) => el.textContent.trim());
    console.log(`Hero Title: "${heroTitle}"`);
    console.log(`Eyebrow: "${eyebrow}"`);
    console.log(`Status Pill: "${statusPill}"`);
    if (!statusPill.includes('30 Available')) throw new Error(`Expected 30 Available, got: ${statusPill}`);

    // Verify 8 Topic Cards in flat grid
    const topicCards = await page.$$eval('.topic-card', (cards) =>
      cards.map((c) => ({
        title: c.querySelector('.topic-card-title')?.textContent.trim(),
        badge: c.querySelector('.topic-badge')?.textContent.trim(),
        desc: c.querySelector('.topic-card-desc')?.textContent.trim(),
        status: c.querySelector('.topic-status-meta')?.textContent.trim(),
        action: c.querySelector('.topic-card-action')?.textContent.trim() || c.querySelector('.topic-card-action-disabled')?.textContent.trim(),
        href: c.getAttribute('href'),
        accent: c.style.getPropertyValue('--topic-accent').trim(),
        isLive: c.classList.contains('topic-card-active'),
        isSoon: c.classList.contains('topic-card-soon'),
      }))
    );

    console.log(`Found ${topicCards.length} Technology Topic Cards:`);
    topicCards.forEach((t, idx) => {
      console.log(`  ${idx + 1}. [${t.title}] Accent: ${t.accent} | Badge: ${t.badge} | Action: ${t.action} | Link: ${t.href || 'NONE'}`);
    });

    if (topicCards.length !== 8) throw new Error(`Expected exactly 8 topic cards, found ${topicCards.length}`);

    // Verify Linux card is live and linked
    const linuxCard = topicCards.find((t) => t.title === 'Linux');
    if (!linuxCard || !linuxCard.isLive || linuxCard.href !== '/challenges/linux' || !linuxCard.badge.includes('30 Challenges')) {
      throw new Error(`Linux card validation failed: ${JSON.stringify(linuxCard)}`);
    }

    // Verify remaining 7 cards are COMING SOON and not linked
    const soonCards = topicCards.filter((t) => t.title !== 'Linux');
    if (soonCards.length !== 7) throw new Error(`Expected 7 coming soon cards, got ${soonCards.length}`);
    for (const sc of soonCards) {
      if (!sc.isSoon || sc.href || sc.badge !== 'COMING SOON') {
        throw new Error(`Coming soon card invalid: ${JSON.stringify(sc)}`);
      }
    }

    // Verify distinct accent colors
    const accents = new Set(topicCards.map((t) => t.accent));
    if (accents.size !== 8) throw new Error(`Expected 8 distinct accent colors, found ${accents.size}`);

    await saveScreenshots(page, 'tech-catalogue-landing');

    // -------------------------------------------------------------
    // 2. Mobile: Technology Catalogue Layout (390x844)
    // -------------------------------------------------------------
    console.log('\n=== 2. Verifying Mobile Viewport on Technology Catalogue (390x844) ===');
    await page.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true });
    await page.goto(`${baseUrl}/challenges`, { waitUntil: 'networkidle2' });

    const gridColumns = await page.$eval('.topic-cards-grid', (el) => window.getComputedStyle(el).gridTemplateColumns);
    console.log(`Mobile topic cards grid columns: ${gridColumns}`);

    await saveScreenshots(page, 'mobile-tech-catalogue');

    // -------------------------------------------------------------
    // 3. Desktop: Difficulty Selection Page (/challenges/linux)
    // -------------------------------------------------------------
    console.log('\n=== 3. Navigating to Difficulty Selection (/challenges/linux) ===');
    await page.setViewport({ width: 1440, height: 900, isMobile: false });
    await page.goto(`${baseUrl}/challenges`, { waitUntil: 'networkidle2' });
    await page.click('a[href="/challenges/linux"]');
    await page.waitForSelector('.challenges-overview-row', { timeout: 5000 });
    console.log(`Current URL: ${page.url()}`);

    const linuxBreadcrumb = await page.$eval('.crumb', (el) => el.textContent.trim());
    console.log(`Breadcrumbs: "${linuxBreadcrumb}"`);
    if (!linuxBreadcrumb.includes('Challenges') || !linuxBreadcrumb.includes('Linux Troubleshooting')) {
      throw new Error(`Unexpected breadcrumbs: ${linuxBreadcrumb}`);
    }

    const begCount = await page.$eval('.overview-beginner .overview-count', (el) => el.textContent.trim());
    const intCount = await page.$eval('.overview-intermediate .overview-count', (el) => el.textContent.trim());
    const advCount = await page.$eval('.overview-advanced .overview-count', (el) => el.textContent.trim());
    console.log(`Difficulty counts: Beginner=${begCount}, Intermediate=${intCount}, Advanced=${advCount}`);
    if (begCount !== '10' || intCount !== '10' || advCount !== '10') {
      throw new Error(`Expected 10/10/10 counts, got ${begCount}/${intCount}/${advCount}`);
    }

    await saveScreenshots(page, 'linux-difficulty-selection');

    // -------------------------------------------------------------
    // 4. Desktop: Challenge Listing Page (/challenges/linux/level/advanced)
    // -------------------------------------------------------------
    console.log('\n=== 4. Navigating to Challenge Listing (/challenges/linux/level/advanced) ===');
    await page.click('.overview-advanced');
    await page.waitForSelector('.challenge-row', { timeout: 5000 });
    console.log(`Current URL: ${page.url()}`);

    const advTitle = await page.$eval('.page-title', (el) => el.textContent.trim());
    const challengeRows = await page.$$('.challenge-row');
    console.log(`Listing Page Title: "${advTitle}", Found ${challengeRows.length} challenge rows`);
    if (challengeRows.length !== 10) throw new Error(`Expected 10 challenge rows, got ${challengeRows.length}`);

    await saveScreenshots(page, 'advanced-challenge-cards');

    // -------------------------------------------------------------
    // 5. Desktop: Live Challenge Execution (LNX-CH-209)
    // -------------------------------------------------------------
    console.log('\n=== 5. Verifying Live Challenge Execution (/challenges/linux/segfault-coredump-elf-forensics) ===');
    await page.goto(`${baseUrl}/challenges/linux/segfault-coredump-elf-forensics`, { waitUntil: 'networkidle2' });
    await page.waitForSelector('#term', { timeout: 10000 });
    await page.waitForSelector('#status-pill.live', { timeout: 15000 });

    // Type command in live PTY
    await page.click('.xterm');
    await page.keyboard.type('echo LIVE_PTY_READY', { delay: 10 });
    await page.keyboard.press('Enter');

    await page.waitForFunction(() => {
      const el = document.querySelector('.xterm-rows');
      return el && el.innerText.includes('LIVE_PTY_READY');
    }, { timeout: 10000 });

    console.log('PTY keystroke echoed successfully in xterm screen.');
    await saveScreenshots(page, 'live-challenge-execution');

    // -------------------------------------------------------------
    // 6. Reduced Motion Support
    // -------------------------------------------------------------
    console.log('\n=== 6. Verifying Reduced Motion ===');
    await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'reduce' }]);
    await page.goto(`${baseUrl}/challenges`, { waitUntil: 'networkidle2' });
    const dotAnimation = await page.$eval('.live-dot', (el) => window.getComputedStyle(el).animationName);
    console.log(`Live dot animation under reduced motion: "${dotAnimation}"`);
    if (dotAnimation !== 'none') throw new Error(`Expected animation: none, got: ${dotAnimation}`);

    // -------------------------------------------------------------
    // 7. Check Console / Network Problems
    // -------------------------------------------------------------
    console.log('\n=== 7. Checking for Console / Network Problems ===');
    if (problems.length > 0) {
      console.error('Problems found:', problems);
      throw new Error(`Encountered ${problems.length} browser errors`);
    } else {
      console.log('Zero console errors, zero uncaught page errors, zero failed requests.');
    }

    console.log('\nALL BROWSER VERIFICATION CHECKS PASSED SUCCESSFULLY!');
  } finally {
    await browser.close();
    await new Promise((res) => server.close(res));
    try { fs.rmSync(sandboxDir, { recursive: true, force: true }); } catch {}
  }
})();
