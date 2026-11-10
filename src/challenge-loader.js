// Independent loader and catalogue for standalone challenges (challenges/<domain>/<slug>/lab.yaml).
// Completely independent of the guided-lab catalog and roadmap validation.
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const { httpsUrl } = require('./site');
const { CHALLENGE_TOPICS } = require('./challenge-topics');

const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,48}$/;
const LEVELS = ['beginner', 'intermediate', 'advanced'];

// Fixed, server-controlled registry of supported challenge domains and slugs.
// Never construct arbitrary filesystem paths from untrusted user input.
const CHALLENGE_REGISTRY = Object.freeze({
  linux: Object.freeze([
    Object.freeze({ id: 'LNX-CH-001', slug: 'file-directory-permissions' }),
    Object.freeze({ id: 'LNX-CH-002', slug: 'users-groups-access' }),
    Object.freeze({ id: 'LNX-CH-003', slug: 'the-missing-disk' }),
    Object.freeze({ id: 'LNX-CH-004', slug: 'mounting-filesystem-basics' }),
    Object.freeze({ id: 'LNX-CH-005', slug: 'process-service-fundamentals' }),
    Object.freeze({ id: 'LNX-CH-006', slug: 'archive-compression-basics' }),
    Object.freeze({ id: 'LNX-CH-007', slug: 'shell-environment-variables' }),
    Object.freeze({ id: 'LNX-CH-008', slug: 'text-search-grep-pipes' }),
    Object.freeze({ id: 'LNX-CH-009', slug: 'package-management-basics' }),
    Object.freeze({ id: 'LNX-CH-010', slug: 'cron-job-scheduling' }),
    Object.freeze({ id: 'LNX-CH-101', slug: 'broken-deployment' }),
    Object.freeze({ id: 'LNX-CH-102', slug: 'disk-pressure' }),
    Object.freeze({ id: 'LNX-CH-103', slug: 'process-resource' }),
    Object.freeze({ id: 'LNX-CH-104', slug: 'systemd-troubleshooting' }),
    Object.freeze({ id: 'LNX-CH-105', slug: 'network-outage' }),
    Object.freeze({ id: 'LNX-CH-106', slug: 'port-socket-binding-conflict' }),
    Object.freeze({ id: 'LNX-CH-107', slug: 'dns-resolution-troubleshooting' }),
    Object.freeze({ id: 'LNX-CH-108', slug: 'ssh-authentication-troubleshooting' }),
    Object.freeze({ id: 'LNX-CH-109', slug: 'file-descriptor-limit-exhaustion' }),
    Object.freeze({ id: 'LNX-CH-110', slug: 'memory-pressure-oom-killer' }),
    Object.freeze({ id: 'LNX-CH-201', slug: 'directory-spool-arg-max' }),
    Object.freeze({ id: 'LNX-CH-202', slug: 'tcp-accept-queue-saturation' }),
    Object.freeze({ id: 'LNX-CH-203', slug: 'cgroup-cfs-throttling' }),
    Object.freeze({ id: 'LNX-CH-204', slug: 'pmtu-mss-clamping' }),
    Object.freeze({ id: 'LNX-CH-205', slug: 'systemd-dependency-cycle' }),
    Object.freeze({ id: 'LNX-CH-206', slug: 'zombie-process-lifecycle-reaping' }),
    Object.freeze({ id: 'LNX-CH-207', slug: 'multi-thread-deadlock-futex' }),
    Object.freeze({ id: 'LNX-CH-208', slug: 'posix-shm-leak-lifecycle' }),
    Object.freeze({ id: 'LNX-CH-209', slug: 'segfault-coredump-elf-forensics' }),
    Object.freeze({ id: 'LNX-CH-210', slug: 'linux-capabilities-privilege-boundary' }),
  ]),
});

const DOMAIN_METADATA = Object.freeze({
  linux: Object.freeze({
    id: 'linux',
    title: 'Linux Troubleshooting',
    description: 'Real-world incident triage and system troubleshooting in simulated Linux environments.',
  }),
});

function readChallengeYaml(file, problems = []) {
  try {
    let text = fs.readFileSync(file, 'utf8');
    // Preprocess unquoted top-level summary/title scalars that contain internal ": "
    // to preserve existing frozen metadata without requiring file modifications.
    text = text.replace(/^(summary|title):\s+([^\n\r"'].*:[^\n\r]*)$/gm, (m, key, val) => `${key}: ${JSON.stringify(val.trim())}`);
    return yaml.load(text) || {};
  } catch (e) {
    problems.push(`${file}: ${e.message.split('\n')[0]}`);
    return null;
  }
}

function createChallengeLoader(opts = {}) {
  const challengesDir = opts.challengesDir || path.join(__dirname, '..', 'challenges');
  const watch = opts.watch === true;

  let canonicalBase = null;
  try {
    canonicalBase = fs.realpathSync(challengesDir);
  } catch {
    canonicalBase = path.resolve(challengesDir);
  }

  // In-memory cache: (domain:slug) -> validated internal challenge representation
  let cache = new Map();
  let loaded = false;

  function resolveEntry(domain, slug) {
    if (typeof domain !== 'string' || typeof slug !== 'string') return null;
    if (!SLUG_RE.test(domain) || !SLUG_RE.test(slug)) return null;
    const entries = CHALLENGE_REGISTRY[domain];
    if (!entries) return null;
    return entries.find((e) => e.slug === slug) || null;
  }

  function validateChallengeDir(domain, entry) {
    if (!canonicalBase || !fs.existsSync(canonicalBase)) return null;

    let targetDir = path.join(challengesDir, domain, entry.slug);
    let found = false;
    try {
      fs.lstatSync(targetDir);
      found = true;
    } catch {
      for (const lvl of LEVELS) {
        const candidate = path.join(challengesDir, domain, lvl, entry.slug);
        try {
          fs.lstatSync(candidate);
          targetDir = candidate;
          found = true;
          break;
        } catch {}
      }
    }
    if (!found) return null;

    try {
      const lstat = fs.lstatSync(targetDir);
      if (lstat.isSymbolicLink()) return null; // Reject symlink escapes

      const canonicalTarget = fs.realpathSync(targetDir);
      // Strict boundary check: target must be contained within canonicalBase
      if (!canonicalTarget.startsWith(canonicalBase + path.sep)) return null;

      const yamlFile = path.join(canonicalTarget, 'lab.yaml');
      if (!fs.existsSync(yamlFile)) return null;
      if (fs.lstatSync(yamlFile).isSymbolicLink()) return null;

      const problems = [];
      const raw = readChallengeYaml(yamlFile, problems);
      if (!raw || problems.length > 0) return null;

      // Validate metadata schema
      if (typeof raw.title !== 'string' || !raw.title.trim()) return null;
      if (!LEVELS.includes(raw.level)) return null;

      // Enforce level hierarchy consistency if located within a level subdirectory
      const parentDirName = path.basename(path.dirname(targetDir));
      if (LEVELS.includes(parentDirName) && raw.level !== parentDirName) return null;
      const minutes = Number(raw.minutes) || 15;
      if (!Number.isFinite(minutes) || minutes <= 0) return null;
      if (typeof raw.summary !== 'string' || !raw.summary.trim()) return null;

      // Validate resources
      const resources = [];
      for (const r of Array.isArray(raw.resources) ? raw.resources : []) {
        if (!r || typeof r.title !== 'string' || !httpsUrl(r.url)) return null;
        resources.push({
          title: r.title,
          url: r.url,
          desc: typeof r.desc === 'string' ? r.desc : '',
        });
      }

      // Validate steps
      if (!Array.isArray(raw.steps) || raw.steps.length === 0) return null;
      const seenStepIds = new Set();
      const steps = [];

      for (const s of raw.steps) {
        if (!s || typeof s.id !== 'string' || !SLUG_RE.test(s.id)) return null;
        if (seenStepIds.has(s.id)) return null;
        seenStepIds.add(s.id);

        if (s.type !== 'lesson' && s.type !== 'task') return null;
        if (typeof s.title !== 'string' || !s.title.trim()) return null;
        if (typeof s.body !== 'string' || !s.body.trim()) return null;

        let hints = [];
        if (s.hint !== undefined && s.hint !== null && s.hint !== '') {
          hints = Array.isArray(s.hint) ? s.hint : [s.hint];
          if (hints.some((h) => typeof h !== 'string' || !h.trim())) return null;
        }

        const step = {
          id: s.id,
          type: s.type,
          title: s.title,
          body: s.body,
          hint: hints[0] || '',
          hints,
          success: typeof s.success === 'string' ? s.success : '',
          hasSetup: false,
        };

        if (s.type === 'task') {
          const checkFile = path.join(canonicalTarget, 'checks', `${s.id}.sh`);
          const solutionFile = path.join(canonicalTarget, 'solutions', `${s.id}.sh`);
          if (!fs.existsSync(checkFile) || fs.lstatSync(checkFile).isSymbolicLink()) return null;
          if (!fs.existsSync(solutionFile) || fs.lstatSync(solutionFile).isSymbolicLink()) return null;

          step.checkFile = checkFile;
          step.solutionFile = solutionFile;

          const setupFile = path.join(canonicalTarget, 'setup', `${s.id}.sh`);
          if (fs.existsSync(setupFile) && !fs.lstatSync(setupFile).isSymbolicLink()) {
            step.setupFile = setupFile;
            step.hasSetup = true;
          }
        }

        steps.push(step);
      }

      return {
        id: entry.id,
        slug: entry.slug,
        domain,
        dir: canonicalTarget,
        title: raw.title.trim(),
        level: raw.level,
        minutes,
        summary: raw.summary.trim(),
        resources,
        steps,
      };
    } catch {
      return null;
    }
  }

  function loadAll() {
    const nextCache = new Map();
    for (const [domain, entries] of Object.entries(CHALLENGE_REGISTRY)) {
      for (const entry of entries) {
        const validated = validateChallengeDir(domain, entry);
        if (validated) {
          nextCache.set(`${domain}:${entry.slug}`, validated);
        }
      }
    }
    cache = nextCache;
    loaded = true;
  }

  function ensureLoaded() {
    if (!loaded || watch) {
      loadAll();
    }
  }

  // Public sanitized projections (strip internal paths & solutions)
  function toSummary(c) {
    return {
      id: c.id,
      slug: c.slug,
      domain: c.domain,
      title: c.title,
      level: c.level,
      minutes: c.minutes,
      summary: c.summary,
      tasksCount: c.steps.filter((s) => s.type === 'task').length,
      stepsCount: c.steps.length,
    };
  }

  function toDetail(c) {
    return {
      id: c.id,
      slug: c.slug,
      domain: c.domain,
      title: c.title,
      level: c.level,
      minutes: c.minutes,
      summary: c.summary,
      tasksCount: c.steps.filter((s) => s.type === 'task').length,
      resources: c.resources,
      steps: c.steps.map((s) => ({
        id: s.id,
        type: s.type,
        title: s.title,
        body: s.body,
        hint: s.hint,
        hints: s.hints,
        success: s.success,
        hasSetup: s.hasSetup,
      })),
    };
  }

  return {
    getTopics() {
      ensureLoaded();
      return CHALLENGE_TOPICS.map((topic) => {
        const registered = CHALLENGE_REGISTRY[topic.id] || [];
        const challenges = registered
          .map((e) => cache.get(`${topic.id}:${e.slug}`))
          .filter(Boolean);
        return {
          id: topic.id,
          title: topic.title,
          shortTitle: topic.shortTitle,
          fullName: topic.fullName,
          summary: topic.summary,
          accent: topic.accent,
          icon: topic.icon,
          count: challenges.length,
          isAvailable: challenges.length > 0,
        };
      });
    },

    getDomains() {
      ensureLoaded();
      return Object.keys(CHALLENGE_REGISTRY).map((domainId) => {
        const meta = DOMAIN_METADATA[domainId] || { id: domainId, title: domainId, description: '' };
        const challenges = (CHALLENGE_REGISTRY[domainId] || [])
          .map((e) => cache.get(`${domainId}:${e.slug}`))
          .filter(Boolean);
        return {
          id: meta.id,
          title: meta.title,
          description: meta.description,
          count: challenges.length,
        };
      });
    },

    listChallenges(domain) {
      ensureLoaded();
      if (!CHALLENGE_REGISTRY[domain]) return null;
      const entries = CHALLENGE_REGISTRY[domain];
      const list = [];
      for (const entry of entries) {
        const c = cache.get(`${domain}:${entry.slug}`);
        if (c) list.push(toSummary(c));
      }
      return list;
    },

    getChallenge(domain, slug) {
      ensureLoaded();
      const entry = resolveEntry(domain, slug);
      if (!entry) return null;
      const c = cache.get(`${domain}:${entry.slug}`);
      return c ? toDetail(c) : null;
    },

    getChallengeInternal(domain, slug) {
      ensureLoaded();
      const entry = resolveEntry(domain, slug);
      if (!entry) return null;
      return cache.get(`${domain}:${entry.slug}`) || null;
    },

    validateAll() {
      ensureLoaded();
      const results = [];
      for (const [domain, entries] of Object.entries(CHALLENGE_REGISTRY)) {
        for (const entry of entries) {
          const c = cache.get(`${domain}:${entry.slug}`);
          results.push({
            id: entry.id,
            slug: entry.slug,
            domain,
            valid: !!c,
          });
        }
      }
      return {
        total: results.length,
        validCount: results.filter((r) => r.valid).length,
        results,
      };
    },
  };
}

module.exports = {
  createChallengeLoader,
  CHALLENGE_REGISTRY,
  DOMAIN_METADATA,
  CHALLENGE_TOPICS,
  SLUG_RE,
  LEVELS,
};
