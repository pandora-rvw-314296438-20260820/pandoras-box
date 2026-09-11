const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase', 'migrations', '20260911171500_pandora_multi_capability_workflows_v1.sql'),
  'utf8',
);
const mobile = readFileSync(
  join(root, 'apps', 'pandora-mobile', 'lib', 'core', 'data', 'pandora_intelligence_api.dart'),
  'utf8',
);

test('multi-capability router creates an ordered governed workflow and never claims completion', () => {
  assert.match(migration, /pandora_multi_capability_workflow_v1/);
  assert.match(migration, /executionMode','sequential_governed'/);
  assert.match(migration, /'verifiedComplete',false/);
  assert.match(migration, /ordered_step_execution/);
  assert.match(migration, /provider_readback_per_step/);
  assert.match(migration, /final_workflow_verification/);
});

test('canonical analytics to code to fix to deploy request preserves step order', () => {
  const analytics = migration.indexOf("private.pandora_workflow_step_v1(v_registry,1,'posthog','analytics.read'");
  const codeRead = migration.indexOf("private.pandora_workflow_step_v1(v_registry,2,'github','repository.read'");
  const codeWrite = migration.indexOf("private.pandora_workflow_step_v1(v_registry,3,'github','repository.write'");
  const deploy = migration.indexOf("private.pandora_workflow_step_v1(v_registry,4,'vercel','deployment.write'");
  assert.ok(analytics >= 0);
  assert.ok(codeRead > analytics);
  assert.ok(codeWrite > codeRead);
  assert.ok(deploy > codeWrite);
});

test('workflow fails closed when any runtime authority is unavailable', () => {
  assert.match(migration, /runtime_authority_unavailable/);
  assert.match(migration, /allRuntimeAuthorityAvailable/);
  assert.match(migration, /Nothing has been executed/);
});

test('multi-capability workflow records one ProjectOS intake instead of bypassing governance', () => {
  assert.match(migration, /projectos_accept_intake/);
  assert.match(migration, /source','projectos_intake'/);
  assert.doesNotMatch(migration, /private\.pandora_integration_github_api_20260825\('(?:POST|PUT|PATCH|DELETE)'/);
});

test('v5 delegates single-capability commands to v4 and is authenticated-only', () => {
  assert.match(migration, /return public\.pandora_chat_universal_dispatch_v4/);
  assert.match(migration, /revoke all on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) to authenticated/);
});

test('mobile uses universal dispatch v5', () => {
  assert.match(mobile, /pandora_chat_universal_dispatch_v5/);
  assert.doesNotMatch(mobile, /pandora_chat_universal_dispatch_v4/);
});
