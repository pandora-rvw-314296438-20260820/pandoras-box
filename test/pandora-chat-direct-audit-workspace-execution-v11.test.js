const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260913093000_pandora_chat_direct_audit_workspace_execution_v11.sql',
  'utf8',
);
const intelligence = fs.readFileSync(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  'utf8',
);
const ask = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);

test('selected-project repository reads are Vault-backed, GET-only, and project-bound', () => {
  assert.match(migration, /pandora_project_github_read_v1/);
  assert.match(migration, /'GET'::extensions\.http_method/);
  assert.match(migration, /name='Github_supabase'/);
  assert.match(migration, /p\.repository=v_repo/);
  assert.match(migration, /p\.organization_id=p_organization_id/);
  assert.match(migration, /pandora_project_github_path_not_allowed/);
  assert.doesNotMatch(migration, /grant execute on function private\.pandora_project_github_read_v1\([^;]+authenticated/);
});

test('repository snapshot is exact-head, bounded, text-only, and excludes credential-shaped files', () => {
  assert.match(migration, /pandora_chat_repository_snapshot_v1/);
  assert.match(migration, /'\/branches\/'\|\|v_default_branch/);
  assert.match(migration, /v_head_sha := nullif\(v_branch_body#>>'\{commit,sha\}',''\)/);
  assert.match(migration, /v_tree_sha := nullif\(v_commit_body#>>'\{tree,sha\}',''\)/);
  assert.match(migration, /'\/git\/trees\/'\|\|v_tree_sha\|\|'\?recursive=1'/);
  assert.match(migration, /p_max_bytes integer default 110000/);
  assert.match(migration, /p_max_files integer default 80/);
  assert.match(migration, /\.env/);
  assert.match(migration, /pem\|key\|p12\|pfx\|jks\|keystore/);
  assert.match(migration, /'truncated',v_truncated/);
  assert.match(migration, /'emptyRepository',true/);
  assert.match(migration, /'repositoryState','empty'/);
  assert.match(migration, /grant execute on function public\.pandora_chat_repository_snapshot_v1[^;]+authenticated/s);
});

test('read-only audits bypass inert research intake while project changes use the real workspace handoff', () => {
  assert.match(migration, /create or replace function public\.pandora_chat_universal_dispatch_v9/);
  assert.match(migration, /'handled',false[\s\S]*'routing','repository_audit_direct'/);
  assert.match(migration, /'intent','project_workspace_change'/);
  assert.match(migration, /'source','project_workspace_change'/);
  assert.match(migration, /return public\.pandora_chat_universal_dispatch_v8/);
});

test('mobile attaches verified repository source to audit turns and uses dispatcher v9', () => {
  assert.match(intelligence, /pandora_chat_repository_snapshot_v1/);
  assert.match(intelligence, /Pandora-verified repository snapshot part/);
  assert.match(intelligence, /If emptyRepository is true/);
  assert.match(intelligence, /If truncated is true/);
  assert.match(intelligence, /pandora_chat_universal_dispatch_v9/);
  assert.match(intelligence, /final String\? source;/);
  assert.match(intelligence, /source: _optionalText\(handoffJson\['source'\]\)/);
});

test('explicit project handoffs execute in Universal Chat through the real builder', () => {
  assert.match(ask, /handoff\?\.source == 'project_workspace_change'/);
  assert.match(ask, /experience\.loadExperience\(handoffProjectId\)/);
  assert.match(ask, /experience\.submitChange\(/);
  assert.match(ask, /experience\.understanding\(/);
  assert.match(ask, /experience\.requestBuild\(/);
  assert.doesNotMatch(ask, /ProjectWorkspaceV2Screen\(/);
  assert.doesNotMatch(ask, /message: handoff\.request/);
});


test('mobile repository audits keep incidental action words read-only but reject explicit action sequences', () => {
  assert.match(intelligence, /final directAction = RegExp/);
  assert.match(intelligence, /final sequenceAction = RegExp/);
  assert.doesNotMatch(intelligence, /final mutating = RegExp/);
});
