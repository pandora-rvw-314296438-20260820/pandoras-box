import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationPath = new URL(
  '../supabase/migrations/20260914100000_pandora_activity_realtime_transport_v1.sql',
  import.meta.url,
);
const edgePath = new URL(
  '../supabase/functions/pandora-intelligence-chat/index.ts',
  import.meta.url,
);
const edgeActivityPath = new URL(
  '../supabase/functions/pandora-intelligence-chat/activity.ts',
  import.meta.url,
);
const mobileApiPath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_activity_stream_api.dart',
  import.meta.url,
);
const intelligencePath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  import.meta.url,
);
const chatPath = new URL(
  '../apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  import.meta.url,
);

const [migration, edge, edgeActivity, mobileApi, intelligence, chat] =
  await Promise.all([
    readFile(migrationPath, 'utf8'),
    readFile(edgePath, 'utf8'),
    readFile(edgeActivityPath, 'utf8'),
    readFile(mobileApiPath, 'utf8'),
    readFile(intelligencePath, 'utf8'),
    readFile(chatPath, 'utf8'),
  ]);
test('M1-004 creates neutral durable activity transport with replay and realtime', () => {
  assert.match(migration, /create table if not exists public\.pandora_activity_jobs/);
  assert.match(migration, /create table if not exists public\.pandora_activity_events/);
  assert.match(migration, /pandora_activity_job_begin_v1/);
  assert.match(migration, /pandora_activity_admit_event_v1/);
  assert.match(migration, /pandora_activity_replay_v1/);
  assert.match(migration, /historyGapDueToRetention/);
  assert.match(migration, /alter publication supabase_realtime add table public\.pandora_activity_events/);
  assert.match(migration, /to service_role/);
  assert.match(migration, /Request accepted by Pandora runtime\./);
});

test('event admission is ordered, terminal-safe, and stores canonical events', () => {
  assert.match(migration, /v_sequence <> v_job\.last_sequence \+ 1/);
  assert.match(migration, /v_job\.terminal_state is not null/);
  assert.match(migration, /p_event->>'schemaVersion'/);
  assert.match(migration, /p_event->>'jobId'/);
  assert.match(migration, /unique \(job_id, event_id\)/);
  assert.match(migration, /primary key \(job_id, sequence\)/);
});

test('intelligence runtime emits real admitted, model, checking, and verified result events', () => {
  assert.match(edge, /requireActivityJob/);
  assert.match(edge, /bindActivityThread/);
  assert.match(edge, /state:"planning"/);
  assert.match(edge, /state:"acting"/);
  assert.match(edge, /state:"checking"/);
  assert.match(edge, /state:"result"/);
  assert.match(edge, /verification_receipt/);
  assert.match(edgeActivity, /pandora_activity_admit_event_v1/);
});
test('mobile starts the activity job before the model turn and consumes replay plus live rows', () => {
  assert.match(intelligence, /startChatExecution/);
  assert.match(intelligence, /activityJobId: jobId/);
  assert.match(intelligence, /activity\.watchJob\(jobId\)/);
  assert.match(chat, /startChatExecution\(/);
  assert.match(mobileApi, /pandora_activity_job_begin_v1/);
  assert.match(mobileApi, /pandora_activity_replay_v1/);
  assert.match(mobileApi, /historyGapDueToRetention/);
  assert.match(mobileApi, /pandora_activity_events/);
  assert.match(mobileApi, /sequence != cursor \+ 1/);
});

test('transport never grants client write access to canonical activity events', () => {
  assert.match(migration, /revoke all on table public\.pandora_activity_events from public, anon, authenticated/);
  assert.doesNotMatch(mobileApi, /\.insert\(/);
  assert.doesNotMatch(mobileApi, /\.update\(/);
  assert.doesNotMatch(mobileApi, /pandora_activity_admit_event_v1/);
});
