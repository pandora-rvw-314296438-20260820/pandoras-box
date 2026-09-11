import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';

const root = join(__dirname, '..');
const migrationPath = join(
  root,
  'supabase',
  'migrations',
  '20260911121500_pandora_provider_connection_semantics_v4.sql',
);
const apiPath = join(
  root,
  'apps',
  'pandora-mobile',
  'lib',
  'core',
  'data',
  'pandora_intelligence_api.dart',
);

const migration = await readFile(migrationPath, 'utf8');
const api = await readFile(apiPath, 'utf8');

test('provider semantics require fresh usable runtime authority', () => {
  assert.match(migration, /pandora_plugin_runtime_registry_v4/);
  assert.match(migration, /pandora_plugin_runtime_registry_v3/);
  assert.match(migration, /usableRuntimeAuthority/);
  assert.match(migration, /state' = 'Connected'/);
  assert.match(migration, /health,canUseNow/);
  assert.match(migration, /vault_credential_plus_fresh_provider_health/);
  assert.match(migration, /management_credential_plus_fresh_provider_health/);
  assert.match(migration, /fresh_projectos_provider_health/);
  assert.match(migration, /query_credential_plus_fresh_provider_health/);
  assert.match(migration, /ingest tokens never count as query authority/);
  assert.match(migration, /verified_google_workspace_authorization/);
});

test('provider actions fail closed when runtime authority is unusable', () => {
  assert.match(
    migration,
    /'available', p\.usable and coalesce\(\(a\.action->>'available'\)::boolean,false\)/,
  );
  assert.match(migration, /'connected', p\.usable/);
  assert.match(migration, /'canUseNow', p\.usable/);
  assert.match(migration, /revoke all on function public\.pandora_plugin_runtime_registry_v4\(uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_plugin_runtime_registry_v4\(uuid\) to authenticated/);
});

test('mobile Plugins reads provider-semantics registry v4', () => {
  assert.match(api, /pandora_plugin_runtime_registry_v4/);
  assert.doesNotMatch(api, /rpc\(\s*'pandora_plugin_runtime_registry_v3'/);
});
