import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile(
  'supabase/migrations/20260912033000_pandora_project_context_resolution_v1.sql',
  'utf8',
);

test('project resolver only uses explicit high-confidence existing-system identity', () => {
  assert.match(migration, /exact_repository/);
  assert.match(migration, /canonical_alias/);
  assert.match(migration, /project_key/);
  assert.match(migration, /repository_name/);
  assert.match(migration, /project_name/);
  assert.match(migration, /multiple_existing_projects_match/);
  assert.match(migration, /no_high_confidence_existing_project_match/);
});

test('project resolver never creates a project and fails closed on ambiguity', () => {
  assert.doesNotMatch(migration, /projectos_register_project\s*\(/);
  assert.match(migration, /v_project_context->>'state'='ambiguous'/);
  assert.match(migration, /I will not guess or create a duplicate project/);
  assert.match(migration, /'intent','clarify_project'/);
  assert.match(migration, /'needsClarification',true/);
});

test('resolved project context is passed into both workflow and single-command routes', () => {
  assert.match(migration, /v_effective_project_id := nullif\(v_project_context->>'projectId',''\)::uuid/);
  assert.match(migration, /pandora_multi_capability_workflow_v1\([\s\S]*v_effective_project_id/);
  assert.match(migration, /pandora_chat_universal_dispatch_v4\([\s\S]*v_effective_project_id/);
  assert.match(migration, /'projectContext',v_project_context/);
});

test('resolver is private and dispatcher remains authenticated-only', () => {
  assert.match(migration, /revoke all on function private\.pandora_resolve_project_context_v1\(uuid,text,uuid\) from public, anon, authenticated/);
  assert.match(migration, /grant execute on function private\.pandora_resolve_project_context_v1\(uuid,text,uuid\) to service_role/);
  assert.match(migration, /revoke all on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) from public, anon/);
  assert.match(migration, /grant execute on function public\.pandora_chat_universal_dispatch_v5\(uuid,text,uuid,uuid\) to authenticated/);
});
