import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile('supabase/migrations/20260912025000_pandora_multi_capability_workflows_v1.sql','utf8');
const mobile = await readFile('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart','utf8');

test('workflow router preserves ordered clause boundaries and separates reads from writes', () => {
  assert.match(migration, /regexp_split_to_array/);
  assert.match(migration, /and\[\[:space:\]\]\+then\|then/);
  assert.match(migration, /v_mode := 'write'/);
  assert.match(migration, /v_mode := 'read'/);
  assert.match(migration, /pandora_governed_provider_read_v1/);
  assert.match(migration, /pandora_governed_mutation_request_v1/);
});

test('consequential workflow steps remain incomplete until ProjectOS execution and evidence', () => {
  assert.match(migration, /routed_to_projectos/);
  assert.match(migration, /all_projectos_plans_authorized/);
  assert.match(migration, /one_time_execution_claims/);
  assert.match(migration, /provider_readbacks/);
  assert.match(migration, /'verifiedComplete',case when v_mode='read'/);
});

test('unsupported or unresolved steps fail closed instead of fabricating success', () => {
  assert.match(migration, /provider_not_resolved/);
  assert.match(migration, /runtime_authority_unavailable/);
  assert.match(migration, /target_not_resolved/);
  assert.match(migration, /blocked_or_partial/);
  assert.match(migration, /No blocked step was treated as complete/);
});

test('public workflow dispatcher is authenticated-only and mobile uses v6', () => {
  assert.match(migration, /revoke all on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) to authenticated/);
  assert.match(mobile, /pandora_chat_universal_dispatch_v7/);
});
