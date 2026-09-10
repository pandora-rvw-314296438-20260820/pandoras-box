const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260910103000_pandora_stream_event_impact_classified_v1.sql',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

test('stream event allowlist includes impact_classified', () => {
  assert.match(migration, /pandora_build_stream_events_event_type_check/);
  assert.match(migration, /'impact_classified'/);
});

test('source generator emits impact_classified and preserves write-failure detail', () => {
  assert.match(generator, /queueStreamEvent\(state, "impact_classified"/);
  assert.match(generator, /SOURCE_STREAM_WRITE_FAILED:\$\{detail\}/);
});
