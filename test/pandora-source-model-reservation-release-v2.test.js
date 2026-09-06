import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const sql = readFileSync(
  new URL(
    '../supabase/migrations/20260906020756_pandora_source_model_reservation_release_v2.sql',
    import.meta.url,
  ),
  'utf8',
);

test('source model reservations are released when an attempt gives up ownership', () => {
  assert.match(
    sql,
    /status in \('reserved','settled','retained','denied','released'\)/,
  );
  assert.match(sql, /old\.status='dispatching' and new\.status='queued'/);
  assert.match(sql, /new\.status in \('failed','cancelled','succeeded'\)/);
  assert.match(
    sql,
    /pandora_release_budget\(\s*v_row\.budget_limit_id,\s*v_row\.reservation_micros\s*\)/,
  );
  assert.match(sql, /status='released'/);
});

test('migration backfills leaked reservations from terminal and retried queues', () => {
  assert.match(
    sql,
    /q\.status in \('failed','cancelled','succeeded','queued'\)/,
  );
  assert.match(sql, /r\.dispatch_attempt <= q\.dispatch_count/);
});
