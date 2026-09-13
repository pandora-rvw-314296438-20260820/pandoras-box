import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const mobilePath = new URL('../apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', import.meta.url);
const apiPath = new URL('../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', import.meta.url);
const edgePath = new URL('../supabase/functions/pandora-intelligence-chat/index.ts', import.meta.url);
const migrationPath = new URL('../supabase/migrations/20260913071000_pandora_chat_standing_authority_v8.sql', import.meta.url);

const [mobile, api, edge, migration] = await Promise.all([
  readFile(mobilePath, 'utf8'),
  readFile(apiPath, 'utf8'),
  readFile(edgePath, 'utf8'),
  readFile(migrationPath, 'utf8'),
]);

test('chat stays chronological and opens on the newest turn', () => {
  assert.match(mobile, /class _Conversation extends StatefulWidget/);
  assert.match(mobile, /ScrollController _scrollController/);
  assert.match(mobile, /reverse: false/);
  assert.match(mobile, /_scrollController\.position\.maxScrollExtent/);
  assert.match(mobile, /_scheduleScrollToLatest\(jump: true\)/);
  assert.match(api, /\.order\('created_at', ascending: false\)/);
  assert.match(api, /return latest\.reversed\.toList\(growable: false\)/);
});

test('mobile uses standing-authority dispatch v8', () => {
  assert.match(api, /pandora_chat_universal_dispatch_v8/);
  assert.doesNotMatch(api, /pandora_chat_universal_dispatch_v7/);
  assert.match(migration, /create or replace function public\.pandora_chat_universal_dispatch_v8/);
});

test('status follow-ups read persisted execution truth instead of generic refusal', () => {
  assert.match(migration, /projectos_intake_requests/);
  assert.match(migration, /The execution step is complete\. Pandora is verifying the requested outcome/);
  assert.match(migration, /requestedOutcomeVerified',false/);
  assert.match(migration, /Yes — the work request is accepted\. Pandora will continue automatically/);
});

test('model fallback treats standing authority as default and keeps execution plumbing internal', () => {
  assert.match(edge, /Standing authority is the default for routine authorized work/);
  assert.match(edge, /Never tell the owner to route work through ProjectOS/);
  assert.match(edge, /credentials and side effects stay inside Pandora's capability runtime and Worker C/);
  assert.match(edge, /Never claim an external action started, is running, is happening in the background, is verifying, or completed unless supplied persisted runtime evidence explicitly supports that exact state/);
  assert.match(edge, /Never invent an ETA or time estimate/);
  assert.match(edge, /A handoff is an execution proposal or receipt, never proof that work started/);
});
