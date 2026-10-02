#!/usr/bin/env node
// npm run lab:new <track> <lab-id> ["Lab title"]  - scaffold a lab from templates/lab/
const fs = require('fs');
const path = require('path');
const ID_RE = /^[a-z0-9][a-z0-9-]{0,48}$/;   // keep in sync with src/loader.js (no deps: runs on the host)

const [track, lab, ...titleParts] = process.argv.slice(2);
if (!track || !lab || !ID_RE.test(track) || !ID_RE.test(lab)) {
  console.error('usage: npm run lab:new <track> <lab-id> ["Lab title"]\n  ids: lowercase letters, digits and dashes');
  process.exit(1);
}
const title = titleParts.join(' ') || lab.replace(/-/g, ' ').replace(/^./, (c) => c.toUpperCase());
const src = path.join(__dirname, '..', 'templates', 'lab');
const trackDir = path.join(__dirname, '..', 'labs', track);
const dest = path.join(trackDir, lab);
if (fs.existsSync(dest)) { console.error(`${dest} already exists`); process.exit(1); }

function copy(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const ent of fs.readdirSync(from, { withFileTypes: true })) {
    const f = path.join(from, ent.name);
    const t = path.join(to, ent.name);
    if (ent.isDirectory()) copy(f, t);
    else fs.writeFileSync(t, fs.readFileSync(f, 'utf8').replace(/__TITLE__/g, title));
  }
}
copy(src, dest);

const trackFile = path.join(trackDir, 'track.yaml');
if (!fs.existsSync(trackFile)) {
  fs.writeFileSync(trackFile, `title: ${track.replace(/-/g, ' ')}\ndescription: TODO describe this track\nlabs:\n  - ${lab}\n`);
  console.log(`created new track ${trackFile} - fix its title/description`);
} else {
  console.log(`Add "  - ${lab}" to the labs: list in ${path.relative(process.cwd(), trackFile)}`);
}
console.log(`created ${path.relative(process.cwd(), dest)}\nnext: edit lab.yaml, then  docker compose run --rm labs node scripts/validate-labs.js --strict ${track}/${lab}`);
