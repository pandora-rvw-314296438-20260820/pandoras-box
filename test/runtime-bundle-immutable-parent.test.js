const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync(
  'supabase/migrations/20260829174000_pandora_runtime_bundle_parent_insert_v1.sql',
  'utf8',
);

test('runtime bundle parent lineage is written only at immutable artifact creation', () => {
  assert.match(source, /artifact_id,parent_version_id,version,content_sha256/);
  assert.match(source, /v_artifact_id,v_existing_root,1,v_bundle_sha/);
  assert.doesNotMatch(source, /update public\.pandora_artifact_versions/i);
  assert.match(source, /project version already bound to different runtime artifact/);
});
