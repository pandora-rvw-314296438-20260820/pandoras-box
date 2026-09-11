const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(join(root, 'supabase', 'migrations', '20260911143500_pandora_governed_mutations_v1.sql'), 'utf8');
const mobile = readFileSync(join(root, 'apps', 'pandora-mobile', 'lib', 'core', 'data', 'pandora_intelligence_api.dart'), 'utf8');

test('mutations enter one governed ProjectOS intake boundary', () => {
  assert.match(migration, /pandora_governed_mutation_request_v1/);
  assert.match(migration, /projectos_accept_intake/);
  assert.match(migration, /idempotencyKey/);
  assert.match(migration, /one_time_execution_claim/);
  assert.match(migration, /provider_readback/);
  assert.match(migration, /verifiedComplete',false/);
});

test('unsupported or unavailable write authority fails closed', () => {
  assert.match(migration, /mutation_route_not_supported/);
  assert.match(migration, /runtime_authority_unavailable/);
  assert.match(migration, /pandora_plugin_runtime_registry_v4/);
  assert.match(migration, /No mutation was executed/);
});

test('public mutation dispatcher is authenticated-only and mobile uses it', () => {
  assert.match(migration, /revoke all on function public\.pandora_chat_universal_dispatch_v4\(uuid,text,uuid,uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_chat_universal_dispatch_v4\(uuid,text,uuid,uuid\) to authenticated/);
  assert.match(mobile, /pandora_chat_universal_dispatch_v5/);
});
