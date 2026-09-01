
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260901140500_pandora_live_build_protocol_v2.sql',
  'utf8',
);
const protocol = fs.readFileSync(
  'docs/pandora-live-build-protocol-v2.md',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

test('protocol v2 allocates an explicit monotonic sequence per stream', () => {
  assert.match(migration, /add column if not exists last_sequence bigint not null default 0/);
  assert.match(migration, /add column if not exists sequence bigint/);
  assert.match(migration, /pandora_build_stream_events_stream_sequence_uq/);
  assert.match(migration, /set last_sequence = s\.last_sequence \+ 1/);
  assert.match(migration, /new\.sequence := v_sequence/);
  assert.match(migration, /new\.event_schema_version := 2/);
  assert.match(protocol, /streamId \+ sequence/);
});

test('replay is ordered, watermarked, gap-aware, and membership-bound', () => {
  assert.match(migration, /pandora_build_stream_replay_v2/);
  assert.match(migration, /m\.user_id = auth\.uid\(\)/);
  assert.match(migration, /m\.status::text = 'active'/);
  assert.match(migration, /e\.sequence > p_after_sequence/);
  assert.match(migration, /e\.sequence <= v_watermark/);
  assert.match(migration, /order by e\.sequence/);
  assert.match(migration, /historyGapDueToRetention/);
  assert.match(migration, /oldestRetainedSequence/);
  assert.match(protocol, /subscribe-then-replay/i);
  assert.match(protocol, /Merge replay and live events by `\(streamId, sequence\)`/);
});

test('stream retention separates live source from durable projections', () => {
  assert.match(migration, /retention_class in \('ephemeral','durable_projection'\)/);
  assert.match(migration, /interval '20 minutes'/);
  assert.match(migration, /interval '30 days'/);
  assert.match(migration, /pandora_cleanup_expired_build_stream_events_v2/);
  assert.match(migration, /pandora-build-stream-cleanup-v2/);
  assert.match(protocol, /do not fabricate expired source/i);
  assert.match(protocol, /Permanent execution evidence remains in BuildJob\/step\/event\/version\/verification records/);
});

test('customer cannot forge stream authority or inject oversized payloads', () => {
  assert.match(migration, /BUILD_STREAM_SESSION_MISMATCH/);
  assert.match(migration, /BUILD_STREAM_JOB_MISMATCH/);
  assert.match(migration, /octet_length\(new\.safe_payload::text\) > 32768/);
  assert.match(migration, /BUILD_STREAM_NON_CODE_CONTENT_FORBIDDEN/);
  assert.match(migration, /revoke all on function public\.pandora_build_stream_replay_v2/);
  assert.match(migration, /grant execute on function public\.pandora_build_stream_replay_v2[\s\S]*to authenticated/);
  assert.match(protocol, /Client roles have read-only access to stream rows/);
});

test('canonical provider source assembly still preserves arbitrary stream chunk text', () => {
  assert.equal(
    generator.includes('return typeof value === "string" ? value : "";'),
    true,
  );
  assert.equal(
    generator.includes('parts.map((part) => text(rec(part).text))'),
    false,
  );
  assert.match(generator, /new TextDecoder\(\)/);
  assert.match(generator, /decoder\.decode\(chunk\.value, \{ stream: true \}\)/);
});
