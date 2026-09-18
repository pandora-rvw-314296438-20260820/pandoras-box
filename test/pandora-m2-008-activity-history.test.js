import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const historyMigrationPath = new URL(
  '../supabase/migrations/20260915104500_pandora_activity_history_v1.sql',
  import.meta.url,
);
const transportMigrationPath = new URL(
  '../supabase/migrations/20260914100000_pandora_activity_realtime_transport_v1.sql',
  import.meta.url,
);
const historyApiPath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_activity_history_api.dart',
  import.meta.url,
);
const streamApiPath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_activity_stream_api.dart',
  import.meta.url,
);

const [historyMigration, transportMigration, historyApi, streamApi] =
  await Promise.all([
    readFile(historyMigrationPath, 'utf8'),
    readFile(transportMigrationPath, 'utf8'),
    readFile(historyApiPath, 'utf8'),
    readFile(streamApiPath, 'utf8'),
  ]);

test('M2-008 preserves the live replay requester and active-membership privacy boundary', () => {
  assert.match(transportMigration, /requested_by=auth\.uid\(\)/);
  assert.match(historyMigration, /m\.user_id=v_uid/);
  assert.match(historyMigration, /m\.status='active'/);
  assert.match(historyMigration, /p_requested_by <> v_uid/);
  assert.match(historyMigration, /v_effective_requested_by := v_uid/);
  assert.match(historyMigration, /j\.requested_by=v_effective_requested_by/);
  assert.doesNotMatch(historyMigration, /v_role in \('owner','admin'\)/);
});

test('M2-008 rejects null and out-of-range limits before SQL LIMIT can become unbounded', () => {
  assert.match(
    historyMigration,
    /p_limit is null or p_limit < 1 or p_limit > 200/,
  );
  assert.match(historyMigration, /limit p_limit \+ 1/);
  assert.match(historyMigration, /limit p_limit/);
  assert.match(historyApi, /query\.limit < 1 \|\| query\.limit > 200/);
  assert.match(historyApi, /'p_limit': query\.limit/);
});

test('History is a read projection of canonical events with stable replay ordering and cursor identity', () => {
  assert.match(historyMigration, /'event',event/);
  assert.match(historyMigration, /order by e\.admitted_at desc,e\.job_id desc,e\.sequence desc/);
  assert.match(historyMigration, /\(e\.admitted_at,e\.job_id,e\.sequence\) < \(p_before_admitted_at,p_before_job_id,p_before_sequence\)/);
  assert.match(historyMigration, /'admittedAt',v_next_at/);
  assert.match(historyMigration, /'jobId',v_next_job/);
  assert.match(historyMigration, /'sequence',v_next_sequence/);
  assert.match(historyMigration, /'retentionBoundary','canonical_event_retention'/);
  assert.doesNotMatch(historyMigration, /insert into public\.pandora_activity_events/i);
  assert.doesNotMatch(historyMigration, /update public\.pandora_activity_events/i);
});

test('live Theatre and History consume the same public projection helper and frozen event contract', () => {
  assert.match(
    streamApi,
    /yield pandoraActivityPublicProjection\(validateEvent\(event\)\)/,
  );
  assert.match(
    historyApi,
    /PandoraActivityProjection\.fromJson\(\s*pandoraActivityPublicProjection\(canonical\)/,
  );
  assert.match(historyApi, /final canonical = _map\(item\['event'\]\)/);
  assert.doesNotMatch(historyApi, /class .*EventFormat/);
});
