const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');

const migration = readFileSync(
  'supabase/migrations/20260829175000_pandora_runtime_storage_duplicate_replay_v1.sql',
  'utf8',
);

test('runtime finalizer only accepts the exact Supabase Storage duplicate replay shape', () => {
  assert.match(migration, /v_upload\.status=400/);
  assert.match(migration, /KeyAlreadyExists/);
  assert.match(migration, /statusCode'\s*,''\)='409'/);
  assert.doesNotMatch(migration, /status not in \(200,201,400,409\)/);
});

test('duplicate replay is still gated by exact storage readback', () => {
  const duplicate = migration.indexOf('KeyAlreadyExists');
  const readback = migration.indexOf('v_readback.status<>200');
  assert.ok(duplicate > 0);
  assert.ok(readback > duplicate);
  assert.match(migration, /octet_length\(coalesce\(v_readback\.content,''\)\)<>v_bundle_bytes/);
  assert.match(migration, /digest\(convert_to\(coalesce\(v_readback\.content,''\),'utf8'\),'sha256'\)/);
});
