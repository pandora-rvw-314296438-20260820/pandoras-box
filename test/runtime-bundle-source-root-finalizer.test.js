const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync(
  'supabase/migrations/20260829173000_pandora_runtime_bundle_source_root_transition_v1.sql',
  'utf8',
);

test('authorized source snapshot can transition exactly once to Worker D runtime bundle', () => {
  assert.match(source, /artifact_kind='source_snapshot'/);
  assert.match(source, /set parent_version_id=coalesce\(parent_version_id,v_existing_root\)/);
  assert.match(source, /root_artifact_version_id is null or root_artifact_version_id=v_existing_root/);
  assert.match(source, /content_sha256=v_bundle_sha/);
  assert.match(source, /artifact_kind='runtime_bundle'/);
  assert.match(source, /project version already bound to different runtime artifact/);
});
