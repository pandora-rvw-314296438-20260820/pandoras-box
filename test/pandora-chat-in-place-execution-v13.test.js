import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const ask = await readFile(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const v12 = await readFile(
  'supabase/migrations/20260913102500_pandora_chat_speech_act_routing_v12.sql',
  'utf8',
);
const v13 = await readFile(
  'supabase/migrations/20260913122000_pandora_chat_in_place_execution_v13.sql',
  'utf8',
);

test('planning stays intelligence while explicit Build it remains an execution handoff', () => {
  assert.match(v12, /Okay great generate the comprehensive detailed step by step plan on how we are going to build this','project_intelligence'/);
  assert.match(v12, /'Build it','workspace_action'/);
  assert.match(v13, /'source','project_workspace_change'/);
});

test('Universal Chat consumes the project action without automatic navigation', () => {
  assert.match(ask, /handoff\?\.source == 'project_workspace_change'/);
  assert.match(ask, /experience\.loadExperience\(handoffProjectId\)/);
  assert.match(ask, /experience\.submitChange\(/);
  assert.match(ask, /experience\.understanding\(/);
  assert.match(ask, /experience\.requestBuild\(/);
  assert.match(ask, /keep this chat open while Pandora works/);
  assert.doesNotMatch(ask, /ProjectWorkspaceV2Screen\(/);
  assert.doesNotMatch(ask, /Navigator\.of\(context\)\.push/);
});

test('in-place execution is idempotent and fails closed after an uncertain mutation', () => {
  assert.match(
    ask,
    /_keys\.create\(\s*'pandora-chat-project-change'\s*,?\s*\)/,
  );
  assert.match(ask, /idempotencyKey: '\$executionKey:intent'/);
  assert.match(ask, /idempotencyKey: '\$executionKey:build:\$intentId'/);
  assert.match(ask, /mutationAccepted = true/);
  assert.match(ask, /_outcomeUnknown = true/);
  assert.match(ask, /will not retry it automatically/);
});

test('durable dispatch copy states that execution remains in chat', () => {
  assert.match(v13, /I''ll handle this change here in chat/);
  assert.match(v13, /I won''t open another screen/);
  assert.match(v13, /workspace-change-v3-chat-in-place/);
  assert.match(v13, /no automatic screen transition/);
});
