const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const ownerData = read('apps/control-tower/owner-data.js');
const ownerExperience = read('apps/control-tower/owner-screens-experience.js');
const ownerApp = read('apps/control-tower/owner-app.js');
const ownerAuth = read('apps/control-tower/auth.js');
const ownerFirst = read('apps/control-tower/owner-first.js');
const index = read('apps/control-tower/index.html');
const design = read('docs/product/WEB_CONTROL_PLANE_V1.md');

test('Simple Mode uses the canonical five-area primary navigation', () => {
  const block = ownerExperience.match(/const items = \[[\s\S]*?\n  \];/);
  assert.ok(block, 'primary navigation declaration is present');
  const labels = [...block[0].matchAll(/\['[^']+', '([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(labels, ['Home', 'Projects', 'Ask Pandora', 'Needs You', 'Business']);
  assert.match(ownerData, /'home', 'projects', 'project', 'ask', 'needs', 'business'/);
  assert.match(ownerExperience, /data-owner-primary-nav/);
});

test('Ask Pandora uses the bounded authenticated intelligence boundary', () => {
  assert.match(ownerAuth, /ALLOWED_EDGE_FUNCTIONS = new Set\(\['pandora-intelligence-chat'\]\)/);
  assert.match(ownerAuth, /'x-organization-id': config\.organizationId/);
  assert.match(ownerAuth, /sessionStorage: 'memory-only'|authState\.accessToken/);
  assert.match(ownerApp, /invokeFunction\?\.\('pandora-intelligence-chat'/);
  assert.doesNotMatch(ownerAuth, /Github_supabase|gemini_api_key|moonshot_api_key|openai_api_key/i);
});

test('owner decisions converge into Needs You while legacy admin screens remain available', () => {
  assert.match(ownerApp, /needs: renderNeeds/);
  assert.match(ownerApp, /approvals: renderApprovals/);
  assert.match(ownerApp, /navigate\('needs', \{ replace: true \}\)/);
  assert.match(ownerExperience, /Consequential decisions only/);
});

test('Business renders bounded facts without inventing commercial outcomes', () => {
  assert.match(ownerExperience, /state\.business/);
  assert.match(ownerExperience, /pandora-owner-business-v1/);
  assert.match(ownerExperience, /Recorded spend by currency/);
  assert.match(ownerExperience, /No cross-currency totals/);
  assert.match(ownerExperience, /Revenue, ROI, adoption, retention, and customer outcomes remain unavailable/);
  assert.doesNotMatch(ownerExperience, /Business data is not connected to this owner view yet/);
});

test('web control plane design preserves verified Live semantics and Admin safety', () => {
  assert.match(design, /READY is never LIVE/);
  assert.match(design, /approval separate from execution/);
  assert.match(design, /one-time execution claim/);
  assert.match(design, /audit-chain verification/);
  assert.match(design, /no provider credential in browser storage/);
});

test('experience assets are loaded through the owner-first shell', () => {
  assert.match(ownerFirst, /owner-screens-experience\.js/);
  assert.match(index, /owner-experience\.css/);
  assert.match(index, /web-publish-truth-v2-20260907-1/);
});
