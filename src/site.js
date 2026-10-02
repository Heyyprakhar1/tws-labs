// Loader for labs/site.yaml (the channel link and optional extra videos) (channel, videos, upcoming roadmap).
// Never throws: problems are collected so a typo in a contributed file shows up
// as a warning instead of taking the site down.
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const DEFAULT_FILE = path.join(__dirname, '..', 'labs', 'site.yaml');
const DEFAULT_CHANNEL = { name: 'TrainWithShubham', url: 'https://www.youtube.com/@TrainWithShubham' };

// External links in contributed content must be plain https:// URLs.
function httpsUrl(u) {
  try { return new URL(String(u)).protocol === 'https:' ? String(u) : null; } catch { return null; }
}

function readYaml(file, problems) {
  try { return yaml.load(fs.readFileSync(file, 'utf8')) || {}; } catch (e) {
    problems.push(`${file}: ${e.message.split('\n')[0]}`);
    return null;
  }
}

function loadSite(file = DEFAULT_FILE) {
  const problems = [];
  const site = { channel: { ...DEFAULT_CHANNEL }, videos: [], problems };
  if (!fs.existsSync(file)) return site;
  const raw = readYaml(file, problems);
  if (!raw) return site;
  if (raw.channel) {
    if (httpsUrl(raw.channel.url)) site.channel = { name: String(raw.channel.name || 'YouTube'), url: raw.channel.url };
    else problems.push('site.yaml: channel.url must be an https:// URL');
  }
  for (const [n, v] of (Array.isArray(raw.videos) ? raw.videos : []).entries()) {
    if (!v || typeof v.title !== 'string' || !httpsUrl(v.url)) { problems.push(`site.yaml: videos[${n}] needs a title and an https:// url`); continue; }
    site.videos.push({ title: v.title, url: v.url, note: v.note || '' });
  }
  return site;
}

module.exports = { loadSite, httpsUrl, readYaml, yaml, DEFAULT_FILE };
