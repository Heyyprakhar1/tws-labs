#!/usr/bin/env node
// Optional helper - never run by the app or by CI. Reads the public planning sheet and tells you which of its topics
// are not on labs/roadmap.json yet, so the roadmap can follow the sheet without the site ever depending on Google.
//   node scripts/import-roadmap.js                 report only
//   node scripts/import-roadmap.js --write         append the missing topics to roadmap.json as status "later"
//   node scripts/import-roadmap.js --csv file.csv  read a local export instead of the network
// Curated fields (titles, statuses, order) are never touched. Subjects we deliberately leave out are skipped.
const fs = require('fs');
const path = require('path');

const SHEET_ID = '1eE-NhZQFr545LkP4QNhTgXcZTtkMFeEPNyVXAflXia0';
const DEFAULT_GID = '2091219672';
const ROADMAP = path.join(__dirname, '..', 'labs', 'roadmap.json');
// Not learning content, or not part of this AWS-focused platform.
const SKIP_SUBJECT = /^(introduction|job assistance|azure|mini projects|mega project|total hours)$/i;
const SKIP_TOPIC = /^(total hours)$/i;
// Where a new topic lands until someone curates it.
const DOMAIN_OF = [[/agentic|ai\b/i, 'ai'], [/aws|kubernetes|infrastructure|serverless|cloud/i, 'cloud']];

// Minimal RFC-4180 CSV parser (quoted fields, escaped quotes, newlines inside quotes).
function parseCsv(text) {
  const rows = []; let row = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; } else field += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(field); rows.push(row); row = []; field = ''; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

// Turn the sheet's merged-cell layout into [{subject, topic, subtopics, relevance}]. Subject and Topic are only filled
// on the first row of a group, so they carry forward; a row with no Topic adds a sub-topic to the current one.
function parseSheet(csv) {
  const rows = parseCsv(csv);
  const h = rows.findIndex((r) => r.some((c) => c.trim() === 'Subject') && r.some((c) => c.trim() === 'Topic'));
  if (h < 0) throw new Error('could not find the Subject / Topic header row');
  const col = (re, from = 0) => rows[h].findIndex((c, i) => i >= from && re.test(c.trim()));
  const [iSub, iTop, iSt, iRel] = [col(/^Subject$/), col(/^Topic$/), col(/^Sub-?Topics$/), col(/Relevance/i)];
  const out = []; let subject = '', cur = null;
  for (const r of rows.slice(h + 1)) {
    const cell = (i) => (i >= 0 && r[i] ? r[i].replace(/\s+/g, ' ').trim() : '');
    if (cell(iSub)) subject = cell(iSub);
    if (/^total hours$/i.test(subject) || /^total hours$/i.test(cell(iTop))) break;     // everything after is projects
    if (cell(iTop)) {
      cur = { subject, topic: cell(iTop), subtopics: [], relevance: null };
      out.push(cur);
    }
    if (cur && cell(iSt)) cur.subtopics.push(cell(iSt));
    const rel = parseInt(cell(iRel), 10);
    if (cur && Number.isFinite(rel) && cur.relevance === null) cur.relevance = rel;
  }
  return out.filter((t) => !SKIP_SUBJECT.test(t.subject) && !SKIP_TOPIC.test(t.topic));
}

// A sheet topic counts as covered when one of its meaningful words appears in a roadmap topic title or sub-topic.
const words = (s) => s.toLowerCase().replace(/\[[^\]]*\]/g, ' ').split(/[^a-z0-9+#]+/).filter((w) => w.length >= 4 && !['devops', 'with', 'project', 'for', 'fundamentals', 'masterclass'].includes(w));
function missingFrom(roadmap, sheetTopics) {
  const known = roadmap.domains.flatMap((d) => d.topics).map((t) => `${t.title} ${(t.subtopics || []).join(' ')}`.toLowerCase()).join(' | ');
  return sheetTopics.filter((t) => !words(`${t.subject} ${t.topic}`).some((w) => known.includes(w)));
}
const slug = (s) => s.toLowerCase().replace(/\[[^\]]*\]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40);
const domainFor = (t) => (DOMAIN_OF.find(([re]) => re.test(`${t.subject} ${t.topic}`)) || [null, 'devops'])[1];

function addMissing(roadmap, missing) {
  for (const t of missing) {
    const d = roadmap.domains.find((x) => x.id === domainFor(t)) || roadmap.domains[0];
    const item = { id: slug(t.topic), title: t.topic.replace(/\[[^\]]*\]/g, '').trim(), status: 'later', subtopics: t.subtopics.slice(0, 6) };
    if (t.relevance !== null) item.relevance = t.relevance;
    d.topics.push(item);
  }
  return roadmap;
}

async function main() {
  const args = process.argv.slice(2);
  const csvArg = args.indexOf('--csv');
  const csv = csvArg > -1 ? fs.readFileSync(args[csvArg + 1], 'utf8')
    : await (await fetch(`https://docs.google.com/spreadsheets/d/${SHEET_ID}/export?format=csv&gid=${DEFAULT_GID}`)).text();
  const roadmap = JSON.parse(fs.readFileSync(ROADMAP, 'utf8'));
  const missing = missingFrom(roadmap, parseSheet(csv));
  if (!missing.length) return console.log('roadmap.json already covers every topic in the sheet.');
  console.log(`${missing.length} sheet topic(s) not on the roadmap yet:`);
  missing.forEach((t) => console.log(`  - [${domainFor(t)}] ${t.topic}${t.relevance !== null ? ` (relevance ${t.relevance}%)` : ''}`));
  if (args.includes('--write')) {
    fs.writeFileSync(ROADMAP, JSON.stringify(addMissing(roadmap, missing), null, 2) + '\n');
    console.log('added as "later"; review labs/roadmap.json and promote what you want.');
  } else console.log('run again with --write to add them as "later".');
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = { parseCsv, parseSheet, missingFrom, addMissing, domainFor, slug };
