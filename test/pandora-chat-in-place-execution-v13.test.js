import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const [screen, adapters] = await Promise.all(['ask_pandora_screen.dart', 'chat/pandora_chat_action_adapters.dart']
  .map(file => readFile(`apps/pandora-mobile/lib/features/simple/${file}`, 'utf8')));
const ask = [screen, adapters].join('\n');
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
  assert.match(ask, /experience\.loadExperience\(projectId\)/);
  assert.match(ask, /experience\.submitChange\(/);
  assert.match(ask, /experience\.understanding\(/);
  assert.match(ask, /experience\.requestBuild\(/);
  assert.match(ask, /You can follow it in Activity\./);
  assert.doesNotMatch(ask, /ProjectWorkspaceV2Screen\(/);
  const start = screen.indexOf("handoff?.source == 'project_workspace_change'");
  const end = screen.indexOf('if (!_current(token)) return;', start);
  assert.ok(start >= 0 && end > start);
  const projectHandoff = screen.slice(start, end);
  assert.match(projectHandoff, /await _executeProjectHandoff\(dispatch, handoff!\)/);
  assert.doesNotMatch(projectHandoff, /Navigator\.|onCoreNavigate/,
    'consuming a project action must not navigate away from its turn');
  assert.doesNotMatch(adapters, /Navigator\.|onCoreNavigate/,
    'execution adapters must leave navigation to explicit shell actions');
});

test('in-place execution is idempotent and fails closed after an uncertain mutation', () => {
  assert.match(ask, /final token = dispatch\.token/);
  assert.match(ask, /idempotencyKey: '\$\{token\.attemptId\}:intent'/);
  assert.match(ask, /idempotencyKey: '\$\{token\.attemptId\}:build:\$intentId'/);
  assert.match(ask, /mutationAccepted = true/);
  assert.match(ask, /outcomeUnknown: mutationAccepted/);
  assert.match(ask, /recoverable: !mutationAccepted/);
});

test('durable dispatch copy states that execution remains in chat', () => {
  assert.match(v13, /I''ll handle this change here in chat/);
  assert.match(v13, /I won''t open another screen/);
  assert.match(v13, /workspace-change-v3-chat-in-place/);
  assert.match(v13, /no automatic screen transition/);
});
