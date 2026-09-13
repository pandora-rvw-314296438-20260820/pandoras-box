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
const release = fs.readFileSync(
  '.github/workflows/pandora-mobile-release.yml',
  'utf8',
);
const physical = fs.readFileSync(
  'supabase/functions/pandora-physical-android-attestation/contract.mjs',
  'utf8',
);

test('owner read-only audit never terminates as a ProjectOS intake receipt', () => {
  assert.match(migration, /pandora_chat_universal_dispatch_v9/);
  assert.match(migration, /'routing','repository_audit_direct'/);
  assert.match(intelligence, /pandora_chat_repository_snapshot_v1/);
  assert.match(intelligence, /Pandora-verified repository snapshot part/);
  assert.doesNotMatch(
    migration,
    /accepted the (analysis )?request into ProjectOS\. Acceptance is not execution\./,
  );
});

test('Build it / Fix it / Improve it on a selected project enters the real workspace runtime', () => {
  assert.match(migration, /'intent','project_workspace_change'/);
  assert.match(migration, /'source','project_workspace_change'/);
  assert.match(ask, /handoff\?\.source == 'project_workspace_change'/);
  assert.match(ask, /ProjectWorkspaceV2Screen\(/);
  assert.match(ask, /initialChange: handoff!\.request/);
  assert.doesNotMatch(ask, /message: handoff\.request/);
});

test('audit evidence is exact/bounded and empty repositories are reported truthfully', () => {
  assert.match(migration, /'\/branches\/'\|\|v_default_branch/);
  assert.match(migration, /v_head_sha := nullif\(v_branch_body#>>'\{commit,sha\}',''\)/);
  assert.match(migration, /v_tree_sha := nullif\(v_commit_body#>>'\{tree,sha\}',''\)/);
  assert.match(migration, /'emptyRepository',true/);
  assert.match(migration, /'truncated',v_truncated/);
  assert.match(intelligence, /If emptyRepository is true/);
  assert.match(intelligence, /If truncated is true/);
});

test('an APK remains a validation candidate until physical-device evidence exists', () => {
  assert.match(release, /--prerelease/);
  assert.match(release, /Physical-device verification: not yet asserted/);
  assert.match(release, /physical_device_verified=/);
  assert.match(physical, /owner_authenticate/);
  assert.match(physical, /submit_owner_command/);
  assert.match(physical, /observe_durable_dispatch/);
  assert.match(physical, /observe_exact_provider_result/);
  assert.match(physical, /observe_proof_in_owner_read/);
});
