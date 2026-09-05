const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260905062000_pandora_build_stream_replay_retention_gap_v1.sql',
  'utf8',
);

test('replay treats fully expired retained history as a retention gap', () => {
  assert.match(
    migration,
    /v_gap := p_after_sequence < v_watermark[\s\S]*v_oldest_retained is null[\s\S]*p_after_sequence \+ 1 < v_oldest_retained/,
  );
});

test('hasMore means another surviving retained event exists', () => {
  assert.match(migration, /select exists \([\s\S]*e\.expires_at > now\(\)[\s\S]*\) into v_has_more/);
  assert.match(migration, /'hasMore', v_has_more/);
  assert.doesNotMatch(
    migration,
    /'hasMore', coalesce\(v_returned_max, p_after_sequence\) < v_watermark/,
  );
});
