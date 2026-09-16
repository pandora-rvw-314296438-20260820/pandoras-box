const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const source = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260911131000_pandora_universal_capability_router_v2.sql'),
  'utf8',
);

test('Vercel deployment.read uses the bounded Vault-backed adapter', () => {
  assert.match(source, /if v_provider='vercel' and not v_mutating then/);
  assert.match(source, /private\.pandora_exact_vercel_api_20260825/);
  assert.match(source, /'authority','governed_adapter'/);
  assert.match(source, /'action','deployment\.read'/);
  assert.match(source, /'facts',v_facts/);
  assert.match(source, /'sourceSha'/);
  assert.match(source, /'readyState'/);
  assert.match(source, /'readySubstate'/);
  assert.match(source, /concat\('\/',v_production->>'readySubstate'\)/);
  assert.match(source, /concat\(' at source ',v_production #>> '\{meta,githubCommitSha\}'\)/);
});

test('Vercel live read does not persist or return the raw provider body', () => {
  assert.doesNotMatch(source, /'capabilityResult'\s*,\s*v_vercel/);
  assert.doesNotMatch(source, /'capabilityResult'\s*,\s*v_vercel_body/);
  assert.doesNotMatch(source, /'facts'\s*,\s*v_vercel_body/);
  assert.match(source, /Vercel live read could not be verified from the bounded provider adapter/);
});
