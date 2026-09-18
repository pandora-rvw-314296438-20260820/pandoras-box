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
const styles = read('apps/control-tower/owner-experience.css');
const auth = read('apps/control-tower/auth.js');
const first = read('apps/control-tower/owner-first.js');
const screens = read('apps/control-tower/owner-screens.js');
const bootstrap = read('apps/control-tower/bootstrap.js');
const index = read('apps/control-tower/index.html');

test('Professional Mode exposes the owner-facing Enterprise areas', () => {
  const nav = professional.slice(
    professional.indexOf('const PROFESSIONAL_NAV'),
    professional.indexOf(']);', professional.indexOf('const PROFESSIONAL_NAV')) + 3,
  );
  const labels = [...nav.matchAll(/\['[^']+', '([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(labels, [
    'Overview', 'Operations & Bookings', 'Guests & Customers', 'Team & Access',
    'Revenue & Reports', 'Needs You', 'Activity', 'Settings',
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
  assert.match(app, /professionalOverview/);
  assert.match(app, /professionalOperations/);
  assert.match(app, /professionalGuests/);
  assert.match(app, /professionalTeam/);
  assert.match(app, /professionalRevenue/);
  assert.match(app, /professionalNeedsYou/);
  assert.match(app, /professionalActivity/);
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

test('Professional Memory consumes only the bounded canonical status envelope', () => {
  assert.match(professional, /state\.projection\?\.evidence\?\.memory/);
  assert.match(professional, /memory\.healthStatus/);
  assert.match(professional, /memory\.authentication/);
  assert.match(professional, /memory\.approvedRecordIds/);
  assert.match(professional, /memory\.freshestRecordAt/);
  assert.match(professional, /memory\.conflicts/);
  assert.ok(professional.includes('mcpmaster-pandoras-box'));
  assert.ok(professional.includes('Memory contents remain bounded'));
  assert.ok(professional.includes('does not render raw memory contents, proposed evidence bodies, candidate payloads or promotion internals'));
});

test('Professional Library consumes only the bounded operator Library index', () => {
  assert.match(professional, /state\.library/);
  assert.ok(professional.includes('Immutable artifact metadata and project-version lineage'));
  assert.ok(professional.includes('Metadata only'));
  assert.ok(professional.includes('does not expose storage paths, raw provenance, source payloads, deployment URLs, provider deployment IDs or artifact bytes'));
});

test('Professional Business consumes the shared bounded owner contract', () => {
  assert.match(professional, /state\.business/);
  assert.match(professional, /pandora-owner-business-v1/);
  assert.ok(professional.includes('No cross-currency totals'));
  assert.ok(professional.includes('Commercial outcomes are not inferred'));
  assert.ok(professional.includes('Revenue, ROI, adoption, retention, and customer outcomes remain explicitly unavailable'));
  assert.doesNotMatch(professional, /Authoritative business analytics are not connected to this web mode yet/);
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
  assert.ok(first.includes('web-theatre-status-truth-v1-20260910-1'));
  assert.ok(index.includes('owner-experience.css?v=web-professional-mode-v1-20260907-1'));
  assert.ok(index.includes('bootstrap.js?v=web-theatre-status-truth-v1-20260910-1'));
});

test('shared project workspace returns to the active presentation mode', () => {
  const workspace = read('apps/control-tower/owner-project-workspace.js');
  assert.ok(workspace.includes("state.mode === 'professional' ? 'professional-operations' : 'projects'"));
  assert.ok(workspace.includes("state.mode === 'professional' ? 'Operations' : 'Projects'"));
});

test('Enterprise command stays contextual and uses verified activity readback', () => {
  assert.match(app, /ENTERPRISE_ROUTE_CONTEXT/);
  assert.match(app, /data-enterprise-command/);
  assert.match(app, /enterpriseContext/);
  assert.match(app, /beginActivityJob/);
  assert.match(app, /replayActivity/);
  assert.match(auth, /pandora_activity_job_begin_v1/);
  assert.match(auth, /pandora_activity_replay_v1/);
  assert.match(styles, /\.enterprise-command-dock/);
  assert.match(styles, /safe-area-inset-bottom/);
});

test('Team and Access uses the protected organization directory without inventing staff facts', () => {
  assert.match(auth, /'pandora-user-admin'/);
  assert.match(auth, /\^members\$/);
  assert.match(app, /loadTeamMembers/);
  assert.match(professional, /state\.team/);
  assert.match(professional, /Property staff scope is not connected/);
  assert.doesNotMatch(professional, /state\.teamUsers/);
});

test('Enterprise business cards fail closed when PLP operational sources are absent', () => {
  assert.ok(professional.includes('Property operations data is not connected yet'));
  assert.ok(professional.includes('Pandora will not invent occupancy, revenue, arrival, departure, guest, or booking figures'));
  assert.ok(professional.includes('PLP revenue source is not connected'));
  assert.ok(professional.includes('No bounded PLP guest or customer source exists'));
});
