const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const ownerApi = read('supabase/functions/pandora-owner-api/index.ts');
const auth = read('apps/control-tower/auth.js');
const data = read('apps/control-tower/owner-data.js');
const runtime = read('apps/control-tower/owner-runtime.js');
const simple = read('apps/control-tower/owner-screens-experience.js');
const professional = read('apps/control-tower/owner-professional.js');

const business = ownerApi.slice(
  ownerApi.indexOf('const BUSINESS_PROJECT_LIMIT'),
  ownerApi.indexOf('async function home'),
);

test('owner Business route is authenticated, bounded, and organization scoped', () => {
  assert.match(ownerApi, /route === "\/business"/);
  assert.match(business, /BUSINESS_PROJECT_LIMIT = 500/);
  assert.match(business, /BUSINESS_ROW_LIMIT = 5000/);
  assert.match(business, /projectCount <= BUSINESS_PROJECT_LIMIT/);
  assert.match(business, /objectiveCount <= BUSINESS_ROW_LIMIT/);
  assert.match(business, /budgetCount <= BUSINESS_ROW_LIMIT/);
  assert.match(business, /costEntryCount <= BUSINESS_ROW_LIMIT/);
  assert.ok((business.match(/\.eq\("organization_id", context\.organizationId\)/g) || []).length >= 4);
  assert.match(business, /contractVersion: "pandora-owner-business-v1"/);
  assert.match(business, /completeness:/);
});

test('cost and budget aggregation never silently crosses currencies or number precision', () => {
  assert.match(business, /BigInt\(text\)/);
  assert.match(business, /return value\.toString\(\)/);
  assert.match(business, /new Map<string, CostBucket>\(\)/);
  assert.match(business, /new Map<string, BudgetBucket>\(\)/);
  assert.match(business, /costBucket\(portfolioCosts, currency\)/);
  assert.match(business, /budgetBucket\(portfolioBudgets, currency\)/);
  assert.match(business, /currency,/);
  assert.doesNotMatch(business, /Number\(row\.(?:estimated|billed|charged|credit|hard_limit|spent|reserved)/);
});

test('Business owner projection minimizes sensitive/raw ledger fields', () => {
  assert.doesNotMatch(business, /metadata_redacted/);
  assert.doesNotMatch(business, /idempotency_key/);
  assert.doesNotMatch(business, /tool_call_id/);
  assert.doesNotMatch(business, /model_run_id/);
  assert.doesNotMatch(business, /build_job_id/);
  assert.doesNotMatch(business, /cost_category/);
  assert.doesNotMatch(business, /provider,/);
  assert.match(business, /revenue: true/);
  assert.match(business, /roi: true/);
  assert.match(business, /adoption: true/);
  assert.match(business, /retention: true/);
  assert.match(business, /customerOutcomes: true/);
});

test('browser exposes exactly one new read-only owner route for Business', () => {
  const policy = auth.slice(auth.indexOf('const EDGE_ROUTE_POLICIES'), auth.indexOf('const PROJECT_PROJECTION_COLUMNS'));
  assert.match(policy, /\^business\$/);
  assert.match(runtime, /edgeRequest\('pandora-owner-api', \['business'\], \{ method: 'GET' \}\)/);
  assert.doesNotMatch(runtime, /\['business'\][\s\S]{0,120}method: 'POST'/);
  assert.match(data, /business:\s*\{[\s\S]*data: null[\s\S]*loading: false/);
});

test('Business failure is isolated from canonical live readiness', () => {
  assert.match(runtime, /businessPromise[\s\S]*\.catch\(\(error\) => \(\{ data: null, error \}\)\)/);
  const candidate = runtime.slice(runtime.indexOf('const candidate ='), runtime.indexOf('state.health ='));
  assert.doesNotMatch(candidate, /business/);
  assert.match(runtime, /state\.live = readiness\(candidate\)/);
});

test('Simple and Professional modes render the same bounded Business truth', () => {
  for (const surface of [simple, professional]) {
    assert.match(surface, /state\.business/);
    assert.match(surface, /pandora-owner-business-v1/);
    assert.match(surface, /No cross-currency totals/);
    assert.match(surface, /Revenue, ROI, adoption, retention/);
  }
  assert.match(simple, /Recorded spend by currency/);
  assert.match(professional, /Project business truth/);
});

test('protected Business data is cleared on sign-out through owner app state reset', () => {
  const app = read('apps/control-tower/owner-app.js');
  assert.ok((app.match(/state\.business = \{ data: null, loading: false, error: null, loadedAt: null \}/g) || []).length >= 2);
});
