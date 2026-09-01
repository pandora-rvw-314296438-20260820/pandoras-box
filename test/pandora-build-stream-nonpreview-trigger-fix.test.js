
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase/migrations/20260901182500_pandora_build_stream_nonpreview_trigger_fix_v1.sql'),
  'utf8',
);

test('non-preview BuildJob transitions never dereference an unassigned preview record', () => {
  assert.match(migration, /v_preview_version_id uuid := null/);
  assert.match(migration, /if found then\s+v_preview_version_id := v_preview\.version_id;/s);
  assert.match(migration, /when v_event_type = 'preview_ready' then v_preview_version_id/);
  assert.doesNotMatch(migration, /when v_event_type = 'preview_ready' then v_preview\.version_id/);
  assert.match(migration, /when new\.status = 'failed' then 'failed'/);
  assert.match(migration, /when new\.status = 'cancelled' then 'cancelled'/);
});

test('preview_ready remains gated by exact ProjectVersion and provider deployment lineage', () => {
  assert.match(migration, /new\.current_stage = 'preview_ready' and new\.status = 'succeeded'/);
  assert.match(migration, /d\.version_id = v\.id/);
  assert.match(migration, /d\.source_sha256 = v\.source_sha256/);
  assert.match(migration, /d\.artifact_digest = v\.artifact_digest_sha256/);
  assert.match(migration, /d\.source_commit_sha is not distinct from v\.source_commit/);
  assert.match(migration, /if found then\s+v_preview_version_id := v_preview\.version_id;\s+v_event_type := 'preview_ready'/s);
});

test('repair is an in-place Protocol V2 trigger fix, not a parallel stream authority', () => {
  assert.match(migration, /create or replace function private\.pandora_mirror_build_job_to_stream_20260901/);
  assert.doesNotMatch(migration, /create\s+table/i);
  assert.doesNotMatch(migration, /create\s+trigger/i);
  assert.doesNotMatch(migration, /delete\s+from\s+public\.pandora_build_/i);
});
