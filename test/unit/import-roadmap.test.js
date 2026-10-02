const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { parseCsv, parseSheet, missingFrom, addMissing, domainFor } = require('../../scripts/import-roadmap');
const { lintLab } = require('../../src/lint');
const { loadCatalog } = require('../../src/loader');

const CSV = fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'roadmap-sample.csv'), 'utf8');

test('the CSV parser handles quotes, escaped quotes and newlines inside a field', () => {
  assert.deepEqual(parseCsv('a,"b,c","d ""q"" e"\n"x\ny",2\n'), [['a', 'b,c', 'd "q" e'], ['x\ny', '2']]);
});

test('the sheet layout parses: subjects and topics carry forward, sub-topics accumulate, relevance is read, projects and junk are cut', () => {
  const topics = parseSheet(CSV);
  const byTopic = Object.fromEntries(topics.map((t) => [t.topic, t]));
  assert.ok(byTopic['Linux For DevOps'] && byTopic['Docker with Project'] && byTopic['Kafka Essentials']);
  assert.deepEqual(byTopic['Linux For DevOps'].subtopics.length, 2, 'two sub-topic rows were folded into the topic');
  assert.equal(byTopic['Linux For DevOps'].relevance, 95);
  assert.equal(byTopic['Python For DevOps [AI Powered]'].relevance, null);
  assert.equal(byTopic['Python For DevOps [AI Powered]'].subtopics.length, 2, 'a blank-topic row adds a sub-topic to the topic above');
  for (const skipped of ['Azure DevOps', 'Introduction to DevOps and Cloud', 'Linkedin and Resume Building', 'Linux Automation Suite']) assert.ok(!byTopic[skipped], `${skipped} is left out`);
});

test('only genuinely missing topics are reported (Kafka), not ones the roadmap covers under another name', () => {
  const roadmap = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'labs', 'roadmap.json'), 'utf8'));
  const missing = missingFrom(roadmap, parseSheet(CSV));
  assert.deepEqual(missing.map((t) => t.topic), ['Kafka Essentials']);
});

test('--write appends missing topics as "later" with a slug id, in a sensible line, and touches nothing else', () => {
  const roadmap = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'labs', 'roadmap.json'), 'utf8'));
  const before = JSON.stringify(roadmap.domains.flatMap((d) => d.topics.map((t) => [t.id, t.status, t.title])));
  const kafka = parseSheet(CSV).filter((t) => t.topic === 'Kafka Essentials');
  addMissing(roadmap, kafka);
  const added = roadmap.domains.flatMap((d) => d.topics).find((t) => t.id === 'kafka-essentials');
  assert.deepEqual([added.status, added.relevance], ['later', 70]);
  assert.equal(domainFor({ subject: 'Agentic AI', topic: 'x' }), 'ai');
  assert.equal(domainFor({ subject: 'Kubernetes', topic: 'x' }), 'cloud');
  assert.equal(JSON.stringify(roadmap.domains.flatMap((d) => d.topics.filter((t) => t.id !== 'kafka-essentials').map((t) => [t.id, t.status, t.title]))), before);
});

test('every shipped lab follows the house style (lesson first, hints on tasks, small sizes)', () => {
  const catalog = loadCatalog(path.join(__dirname, '..', '..', 'labs'));
  const problems = catalog.tracks.flatMap((t) => t.labs.flatMap((l) => lintLab(l).map((w) => `${t.id}/${l.id}: ${w}`)));
  assert.deepEqual(problems, []);
});

test('the lint catches each convention', () => {
  const lab = { title: 'x'.repeat(60), summary: '', minutes: 40, steps: [{ id: 'a', type: 'task', title: 'ok', body: 'y'.repeat(800), hint: '' }] };
  const text = lintLab(lab).join('\n');
  for (const re of [/title is 60/, /summary is missing/, /minutes is 40/, /start with a lesson/, /body is 800/, /task needs a hint/]) assert.match(text, re);
  assert.match(lintLab({ ...lab, steps: [{ id: 'l', type: 'lesson', title: 't', body: 'b' }] }).join(), /at least one graded task/);
});
