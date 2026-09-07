const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const data = read('apps/control-tower/owner-data.js');
const runtime = read('apps/control-tower/owner-runtime.js');
const app = read('apps/control-tower/owner-app.js');
const professional = read('apps/control-tower/owner-professional.js');
const experience = read('apps/control-tower/owner-screens-experience.js');
const first = read('apps/control-tower/owner-first.js');
const screens = read('apps/control-tower/owner-screens.js');
const bootstrap = read('apps/control-tower/bootstrap.js');
const index = read('apps/control-tower/index.html');

test('Professional Mode exposes exactly the nine canonical areas', () => {
  const nav = professional.slice(
    professional.indexOf('const PROFESSIONAL_NAV'),
    professional.indexOf(']);', professional.indexOf('const PROFESSIONAL_NAV')) + 3,
  );
  const labels = [...nav.matchAll(/\['[^']+', '([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(labels, [
    'Home', 'Build', 'Run', 'Connect', 'Memory', 'Verify', 'Business', 'Library', 'Settings',
  ]);
});

test('Simple Mode keeps its exact five-item primary navigation', () => {
  const nav = experience.slice(
    experience.indexOf('function nav()'),
    experience.indexOf('window.PandorasOwnerExperience'),
  );
  const labels = [...nav.matchAll(/\['[^']+', '([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(labels, ['Home', 'Projects', 'Ask Pandora', 'Needs You', 'Business']);
});

test('Professional Mode is a presentation mode over the existing owner runtime', () => {
  assert.match(data, /PROFESSIONAL_ROUTES/);
  assert.match(data, /pandoras-owner-mode/);
  assert.match(app, /professionalHome/);
  assert.match(app, /professionalBuild/);
  assert.match(app, /professionalRun/);
  assert.match(app, /professionalConnect/);
  assert.match(app, /professionalMemory/);
  assert.match(app, /professionalVerify/);
  assert.match(app, /professionalBusiness/);
  assert.match(app, /professionalLibrary/);
  assert.match(app, /professionalSettings/);
  assert.match(app, /state\.mode === 'professional' \? professionalNav\(\) : nav\(\)/);
  assert.match(runtime, /owner-mode-button/);
  assert.match(runtime, /data-action="switch-mode"/);
});

test('Professional mode does not create a second backend authority', () => {
  assert.match(professional, /deriveProjects\(\)/);
  assert.match(professional, /state\.health/);
  assert.match(professional, /state\.connections/);
  assert.match(professional, /state\.logs/);
  assert.match(professional, /state\.chain/);
  assert.doesNotMatch(professional, /fetch\s*\(/);
  assert.doesNotMatch(professional, /MCPMasterAuth\.edgeRequest/);
  assert.doesNotMatch(professional, /service[_-]?role|Github_supabase|OPENAI_API_KEY|MOONSHOT_API_KEY/i);
});

test('unbacked Professional pages refuse to fabricate data', () => {
  assert.ok(professional.includes('Dedicated Memory data is not bridged into this web view yet'));
  assert.ok(professional.includes('Authoritative business analytics are not connected to this web mode yet'));
  assert.ok(professional.includes('A bounded owner-safe Library index is not connected yet'));
  assert.ok(professional.includes('Pandora will not invent revenue, cost, retention, adoption, ROI'));
});

test('Connect exposes posture but explicitly keeps credentials out of the browser', () => {
  assert.ok(professional.includes('Credentials stay outside the browser'));
  assert.ok(professional.includes('Tokens, private keys and Vault values are never rendered here.'));
  assert.match(professional, /connection\.mutations \? 'Governed changes enabled' : 'Read only'/);
});

test('Verify preserves READY versus LIVE semantics', () => {
  assert.ok(professional.includes('READY is never LIVE'));
  assert.ok(professional.includes('production is Live only after the exact production version and deployment are verified'));
  assert.match(professional, /state\.chain\?\.valid === true/);
  assert.match(professional, /state\.health\?\.protectedRoutesConfigured === true/);
  assert.match(professional, /state\.health\?\.durableLedgerConfigured === true/);
});

test('Admin remains the protected existing advanced control tower', () => {
  assert.ok(professional.includes('href="?advanced=1"'));
  assert.match(bootstrap, /advanced/);
  assert.match(bootstrap, /\/control-tower\/app\.js/);
});

test('Professional Mode assets are composed under one distinct revision', () => {
  assert.ok(first.includes('owner-professional.js'));
  assert.ok(screens.includes('PandorasOwnerProfessional'));
  assert.ok(first.includes('web-professional-mode-v1-20260907-1'));
  assert.ok(index.includes('owner-experience.css?v=web-professional-mode-v1-20260907-1'));
  assert.ok(index.includes('bootstrap.js?v=web-professional-mode-v1-20260907-1'));
});
