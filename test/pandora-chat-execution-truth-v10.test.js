import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationPath = new URL(
  '../supabase/migrations/20260913083557_pandora_chat_execution_truth_v10.sql',
  import.meta.url,
);
const edgePath = new URL(
  '../supabase/functions/pandora-intelligence-chat/index.ts',
  import.meta.url,
);

const migration = await readFile(migrationPath, 'utf8');
const edge = await readFile(edgePath, 'utf8');

test('accepted intake is never represented as running execution or a verified ETA', () => {
  assert.match(migration, /there is no persisted evidence that execution has started/);
  assert.match(migration, /It is not done, and no ETA is verified/);
  assert.match(migration, /Acceptance is not execution/);
  assert.match(migration, /persisted execution evidence says a worker started/);
  assert.match(migration, /thousand years/);
  assert.match(migration, /you said/);
  assert.match(migration, /and\|so/);
});

test('legacy selected pandoras-box context resolves the verified canonical repository without mutating the project', () => {
  assert.match(migration, /explicit_project_canonical_fallback/);
  assert.match(migration, /pandora-rvw-314296438-20260820\/pandoras-box/);
  assert.match(migration, /provider_verified/);
  assert.doesNotMatch(migration, /update\s+public\.pandora_projects/i);
});

test('model fallback cannot turn a handoff into execution theatre', () => {
  assert.match(edge, /model handoff only proposes or records requested work; it is not execution evidence/);
  assert.match(edge, /A handoff is an execution proposal or receipt, never proof that work started/);
  assert.match(edge, /Never invent an ETA or time estimate/);
  assert.match(edge, /executionClaim=handoff\?\.required/);
  assert.match(edge, /this response does not contain persisted execution evidence/);
  assert.match(edge, /will not claim that it started, is running in the background, is verifying, or give an ETA/);
});
