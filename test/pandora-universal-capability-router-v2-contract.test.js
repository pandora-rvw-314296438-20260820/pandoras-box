import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationPath = new URL(
  '../supabase/migrations/20260911131000_pandora_universal_capability_router_v2.sql',
  import.meta.url,
);
const apiPath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  import.meta.url,
);

test('universal router resolves provider and action intent before model chat', async () => {
  const migration = await readFile(migrationPath, 'utf8');
  assert.match(migration, /pandora_chat_universal_dispatch_v2/);
  assert.match(migration, /candidateProviders/);
  assert.match(migration, /repository\.read/);
  assert.match(migration, /project\.read/);
  assert.match(migration, /deployment\.read/);
  assert.match(migration, /analytics\.query/);
  assert.match(migration, /files\.read/);
  assert.match(migration, /sheets\.read/);
  assert.match(migration, /I will not guess or silently chain provider actions/);
  assert.match(migration, /projectRequired',false/);
});

test('universal router preserves governed mutations and vercel ProjectOS intake', async () => {
  const migration = await readFile(migrationPath, 'utf8');
  assert.match(migration, /projectos_accept_intake/);
  assert.match(migration, /deployment\.write/);
  assert.match(migration, /authority','projectos/);
  assert.match(migration, /provider readback and verification succeed/);
  assert.match(migration, /pandora_plugin_runtime_registry_v4/);
  assert.match(migration, /revoke all on function public\.pandora_chat_universal_dispatch_v2\(uuid,text,uuid,uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_chat_universal_dispatch_v2\(uuid,text,uuid,uuid\) to authenticated/);
});

test('mobile sends every ordinary text command through the universal router first', async () => {
  const api = await readFile(apiPath, 'utf8');
  assert.match(api, /pandora_chat_universal_dispatch_v7/);
  assert.match(api, /if \(message\.trim\(\)\.isEmpty\) return null/);
  assert.doesNotMatch(api, /if \(!_mightNeedCapability\(message\)\) return null/);
});
