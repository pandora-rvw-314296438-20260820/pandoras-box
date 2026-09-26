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
const timelineControllerPath = new URL(
  '../apps/pandora-mobile/lib/core/activity/pandora_activity_timeline_controller.dart',
  import.meta.url,
);

const [migration, edge, edgeActivity, mobileApi, intelligence, chat, timelineController] =
  await Promise.all([
    readFile(migrationPath, 'utf8'),
    readFile(edgePath, 'utf8'),
    readFile(edgeActivityPath, 'utf8'),
    readFile(mobileApiPath, 'utf8'),
    readFile(intelligencePath, 'utf8'),
    readFile(chatPath, 'utf8'),
    readFile(timelineControllerPath, 'utf8'),
  ]);
test('M1-004 creates neutral durable activity transport with replay and realtime', () => {
  assert.match(migration, /create table if not exists public\.pandora_activity_jobs/);
  assert.match(migration, /create table if not exists public\.pandora_activity_events/);
  assert.match(migration, /pandora_activity_job_begin_v1/);
  assert.match(migration, /pandora_activity_admit_event_v1/);
  assert.match(migration, /pandora_activity_replay_v1/);
  assert.match(migration, /historyGapDueToRetention/);
  assert.match(migration, /select 1 from pg_publication/);
  assert.match(migration, /where pubname='supabase_realtime'/);
  assert.match(migration, /alter publication supabase_realtime add table public\.pandora_activity_events/);
  assert.match(migration, /to service_role/);
  assert.match(migration, /Request accepted by Pandora runtime\./);
});

test('event admission is ordered, terminal-safe, and stores canonical public events', () => {
  assert.match(migration, /v_sequence <> v_job\.last_sequence \+ 1/);
  assert.match(migration, /v_job\.terminal_state is not null/);
  assert.match(migration, /p_event->>'schemaVersion'/);
  assert.match(migration, /p_event->>'jobId'/);
  assert.match(migration, /p_event->>'writerEpoch'/);
  assert.match(migration, /p_event->>'admittedBy'/);
  assert.match(migration, /requested_by = auth\.uid\(\)/);
  assert.match(migration, /unique \(job_id, event_id\)/);
  assert.match(migration, /primary key \(job_id, sequence\)/);
});

test('intelligence runtime emits real business-action, checking, and verified result events', () => {
  assert.match(edge, /requireActivityJob/);
  assert.match(edge, /pandora_chat_universal_dispatch_v9/);
  assert.match(edge, /Requested action was prepared, but execution is not yet verified\./);
  assert.match(edge, /bindActivityThread/);
  assert.match(edge, /pandora-business-theatre/);
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

test('owner-only read and replay scope cannot broaden Chat visibility', () => {
  assert.match(migration, /create policy pandora_activity_jobs_owner_read/);
  assert.match(migration, /requested_by = auth\.uid\(\)/);
  assert.match(migration, /j\.requested_by = auth\.uid\(\)/);
  assert.match(migration, /requested_by=auth\.uid\(\)/);
  assert.match(migration, /created_by=v_uid/);
});

test('writer epoch and replay gaps fail closed', () => {
  assert.match(migration, /p_event->>'writerEpoch'/);
  assert.match(migration, /p_event->>'admittedBy'/);
  assert.match(migration, /for update/);
  assert.match(migration, /v_sequence <> v_job\.last_sequence \+ 1/);
  assert.match(migration, /historyGapDueToRetention/);
  assert.match(mobileApi, /activity writer rollback/);
  assert.match(mobileApi, /two writers in one activity epoch/);
  assert.match(mobileApi, /requires authoritative recovery/);
});

test('public projection boundary strips internal writer fields', () => {
  assert.match(mobileApi, /pandoraActivityPublicProjection/);
  assert.match(mobileApi, /'projectionVersion': 1/);
  assert.match(mobileApi, /'source': provenance/);
  assert.match(mobileApi, /'evidenceRefs': evidenceRefs/);
  assert.match(mobileApi, /yield pandoraActivityPublicProjection\(validateEvent\(event\)\)/);
});

test('runtime terminalizes failures, handoffs, and clarification turns', () => {
  assert.match(edge, /emitActivityFailure/);
  assert.match(edge, /state:"result"/);
  assert.match(edge, /Requested action was prepared, but execution is not yet verified\./);
  assert.match(edge, /Pandora needs one more detail before acting\./);
  assert.match(edgeActivity, /state: 'failed'/);
  assert.match(edgeActivity, /relation: 'failure'/);
});

test('Chat subscribes before awaiting the final intelligence turn', () => {
  const subscribeAt = chat.indexOf('await _watchActivity(execution)');
  const awaitTurnAt = chat.indexOf('await execution.turn');
  assert.ok(subscribeAt >= 0);
  assert.ok(awaitTurnAt > subscribeAt);
  assert.match(chat, /await _activityController\.bind\(/);
  assert.match(chat, /stream: execution\.events/);
  assert.match(timelineController, /stream\.listen\(/);
  assert.match(timelineController, /if \(_reducer\.isTerminal\)/);
  assert.doesNotMatch(chat, /execution\.events\.listen\(/);
});
