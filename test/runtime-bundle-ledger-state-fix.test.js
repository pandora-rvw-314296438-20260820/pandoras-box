const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260829177000_pandora_runtime_bundle_ledger_state_fix_v1.sql',
  'utf8',
);

test('runtime bundle v1 keeps same-artifact version semantics and preserves source lineage in provenance', () => {
  assert.match(migration, /v_artifact_id,null,1,v_bundle_sha/);
  assert.match(migration, /'sourceArtifactVersionId',v_existing_root/);
  assert.doesNotMatch(migration, /v_artifact_id,v_existing_root,1,v_bundle_sha/);
});

test('claimed Worker D jobs traverse the legal state machine before verification', () => {
  const running = migration.indexOf("set status='running'");
  const waiting = migration.indexOf("set status='waiting_verification'");
  assert.ok(running > 0 && waiting > running);
  assert.match(migration, /where id=v_job.id and status='claimed'/);
  assert.match(migration, /claimed-to-running compare-and-set failed/);
});
