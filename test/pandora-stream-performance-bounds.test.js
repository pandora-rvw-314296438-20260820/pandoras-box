const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260902095600_pandora_stream_event_budget_and_expiry_index_v1.sql',
  'utf8',
);

test('Task105 adds the global expiry cleanup index without changing replay authority', () => {
  assert.match(
    migration,
    /create index if not exists pandora_build_stream_events_expiry_id_idx\s+on public\.pandora_build_stream_events\(expires_at, id\)/i,
  );
  assert.doesNotMatch(migration, /drop\s+policy|disable\s+row\s+level\s+security/i);
});

test('Task106 keeps existing payload/path/log bounds while adding a finite stream budget', () => {
  assert.match(migration, /octet_length\(new\.safe_payload::text\) > 32768/);
  assert.match(migration, /length\(new\.file_path\) > 512/);
  assert.match(migration, /octet_length\(coalesce\(new\.safe_payload->>'text',''\)\) > 8192/);
  assert.match(migration, /v_regular_event_limit constant bigint := 10000/);
  assert.match(migration, /v_terminal_event_limit constant bigint := 10032/);
  assert.match(migration, /BUILD_STREAM_EVENT_BUDGET_EXHAUSTED/);
});

test('budget allocation is serialized before sequence increment for concurrent writers', () => {
  const lock = migration.indexOf('for update;');
  const budget = migration.indexOf('if v_last_sequence >= v_regular_event_limit then');
  const increment = migration.indexOf('v_sequence := v_last_sequence + 1;');
  assert.ok(lock >= 0 && budget > lock && increment > budget);
  assert.match(
    migration,
    /select s\.last_sequence, s\.build_job_id[\s\S]*from public\.pandora_build_stream_sessions s[\s\S]*for update;/,
  );
});

test('budget-1 and budget are regular slots; budget+1 requires terminal reserve', () => {
  function outcome(lastSequence, eventType) {
    const terminal = new Set([
      'job_state',
      'needs_you',
      'build_completed',
      'build_failed',
      'stream_error',
    ]).has(eventType);
    if (lastSequence >= 10000 && (!terminal || lastSequence >= 10032)) {
      return 'BUILD_STREAM_EVENT_BUDGET_EXHAUSTED';
    }
    return lastSequence + 1;
  }

  assert.equal(outcome(9998, 'code_chunk'), 9999);
  assert.equal(outcome(9999, 'code_chunk'), 10000);
  assert.equal(outcome(10000, 'code_chunk'), 'BUILD_STREAM_EVENT_BUDGET_EXHAUSTED');
  assert.equal(outcome(10000, 'stream_error'), 10001);
  assert.equal(outcome(10031, 'build_failed'), 10032);
  assert.equal(outcome(10032, 'stream_error'), 'BUILD_STREAM_EVENT_BUDGET_EXHAUSTED');
});

test('terminal reserve cannot be consumed by normal high-volume event types', () => {
  assert.match(
    migration,
    /v_terminal_reserve_event := new\.event_type in \(\s*'job_state',\s*'needs_you',\s*'build_completed',\s*'build_failed',\s*'stream_error'\s*\)/,
  );
  const reserve = migration.match(/v_terminal_reserve_event := new\.event_type in \([\s\S]*?\);/)[0];
  for (const eventType of ['code_chunk', 'stdout_chunk', 'stderr_chunk', 'file_started', 'file_completed']) {
    assert.doesNotMatch(reserve, new RegExp(`'${eventType}'`));
  }
});
