const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const runtime = readFileSync(
  join(root, 'supabase', 'functions', 'pandora-project-runtime', 'index.ts'),
  'utf8',
);
const migration = readFileSync(
  join(root, 'supabase', 'migrations', '20260831063000_pandora_rollback_worker_c_static_v1.sql'),
  'utf8',
);

function rollbackSource() {
  const start = runtime.indexOf('async function rollbackProject');
  const end = runtime.indexOf('async function reconcileProjectRuntime', start);
  assert.ok(start >= 0 && end > start, 'rollback function must be present');
  return runtime.slice(start, end);
}

test('rollback authorization is derived server-side and never trusted from the request body', () => {
  const source = rollbackSource();
  assert.doesNotMatch(source, /body\.authorizationRef/);
  assert.match(source, /pandora_authorize_production_rollback_20260831/);
  assert.match(source, /authorizationRef !== `worker-c:\$\{actionHash\}`/);
  assert.match(migration, /role::text='owner'/);
  assert.match(migration, /'HIGH','ALLOW','PRODUCTION_MUTATION'/);
  assert.match(migration, /'authorizationRef','worker-c:'\|\|v_action_hash/);
});

test('supabase static production has a governed rollback executor with Worker E verification', () => {
  const source = rollbackSource();
  assert.match(source, /provider === "supabase_static"/);
  assert.match(source, /pandora_execute_supabase_static_rollback_20260831/);
  assert.match(migration, /pandora_publish_supabase_fallback_20260831/);
  assert.match(migration, /pandora_worker_e_verify_supabase_production_20260831/);
  assert.match(migration, /pandora_finalize_verified_production_20260830/);
  assert.match(migration, /v_operation_key,'rollback'/);
  assert.match(migration, /set authorization_ref=v_authorization_ref/);
});

test('vercel rollback keeps target as production candidate until verification and rolls back the prior live version only after verification', () => {
  const source = rollbackSource();
  assert.match(source, /lifecycle_status: "production_candidate"/);
  assert.doesNotMatch(
    source,
    /lifecycle_status: "rolled_back"[\s\S]{0,220}targetVersionId/,
  );
  assert.match(source, /rolledBackFromVersionId: expectedProductionVersionId/);
  assert.match(migration, /pandora_finalize_rollback_source_version_20260831/);
  assert.match(migration, /new\.verification_state='live_verified'/);
  assert.match(migration, /v_from:=\(new\.metadata->>'rolledBackFromVersionId'\)::uuid/);
  assert.match(migration, /set lifecycle_status='rolled_back'/);
});

test('rollback policy identity is immutable and idempotency collisions fail closed', () => {
  assert.match(migration, /ROLLBACK_AUTHORIZATION_COLLISION/);
  assert.match(migration, /tool_name<>'rollback_project'/);
  assert.match(migration, /policy_version<>v_policy_version/);
  assert.match(migration, /idempotency_mode<>'REQUIRED'/);
  assert.match(migration, /v_tool\.idempotency_key<>trim\(p_idempotency_key\)/);
  assert.match(migration, /'production_candidate','rolled_back'/);
});
