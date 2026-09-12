import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const routing = await readFile(
  'supabase/migrations/20260912100000_pandora_universal_chat_repository_targeting_v2.sql',
  'utf8',
);
const transport = await readFile(
  'supabase/migrations/20260912100500_pandora_github_memory_repository_binding_v2.sql',
  'utf8',
);
const mobile = await readFile(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const api = await readFile(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  'utf8',
);

test('video regression: actionable handoff remains in Universal Chat', () => {
  assert.match(mobile, /final handoff = turn\.handoff/);
  assert.match(mobile, /dependencies\.repository\.ask\([\s\S]*message: handoff\.request/);
  assert.doesNotMatch(mobile, /CreateProjectExperienceScreen/);
  assert.doesNotMatch(mobile, /ProjectWorkspaceV2Screen/);
  assert.match(mobile, /Execution stays in this conversation|Universal Chat is the control plane/);
});

test('repository router recognizes provider-verified canonical repos including PLP', () => {
  assert.match(routing, /pandora-rvw-314296438-20260820\/pandoras-box-memory/);
  assert.match(routing, /pandora-rvw-314296438-20260820\/pandoras-box/);
  assert.match(routing, /project_key='plp-boracay'/);
  assert.match(routing, /'repositoryStatus','degraded'/);
  assert.doesNotMatch(routing, /pandora-rvw-314296438-20260820\/plp',\s*'projectId'/);
});

test('build and short follow-ups reuse only an already resolved same-thread target', () => {
  assert.match(routing, /build\|continue\|finish\|run\|test\|implement\|work\|proceed/);
  assert.match(routing, /build it\|build this\|go ahead\|do it\|continue/);
  assert.match(routing, /structured_response->'repositoryTarget'/);
  assert.match(routing, /t\.created_by=auth\.uid\(\)/);
  assert.match(routing, /'resolution','thread_continuation'/);
});

test('target resolution grants no mutation authority and handoff remains ProjectOS-governed', () => {
  assert.match(routing, /pandora_governed_mutation_request_v1/);
  assert.match(routing, /authorization,[\s\S]*one-time claim,[\s\S]*provider readback,[\s\S]*evidence/i);
  assert.match(routing, /'projectRequired',false/);
  assert.match(routing, /'source','projectos_intake'/);
  assert.match(api, /pandora_chat_universal_dispatch_v7/);
});

test('canonical GitHub transport supports all three exact repository ids and remains Vault-backed', () => {
  assert.match(transport, /1345495177\|1346392092/);
  assert.doesNotMatch(transport, /1346543644/);
  assert.match(transport, /name='Github_supabase'/);
  assert.match(transport, /pandoras-box-memory/);
  assert.match(transport, /pandoras-box/);\n  assert.match(transport, /pandora-rvw-314296438-20260820\\/plp/);
  assert.match(transport, /revoke all on function private\.pandora_integration_github_api_20260825\(text,text,jsonb\) from public,anon,authenticated/);
  assert.match(transport, /grant execute on function private\.pandora_integration_github_api_20260825\(text,text,jsonb\) to service_role/);
});
