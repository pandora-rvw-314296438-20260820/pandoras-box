import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile('supabase/migrations/20260912082000_pandora_projectless_action_routing_v1.sql','utf8');
const repositoryTargeting = await readFile('supabase/migrations/20260912100000_pandora_universal_chat_repository_targeting_v2.sql','utf8');
const api = await readFile('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart','utf8');
const screen = await readFile('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart','utf8');
const intelligence = await readFile('supabase/functions/pandora-intelligence-chat/index.ts','utf8');

test('normal conversation is the default and owner/repo mentions do not authorize action', () => {
  assert.match(migration,/Normal chat is the default/);
  assert.match(migration,/repository mention by itself is conversation, not authorization to act/);
  assert.match(migration,/Route only when the owner explicitly asks for an action/);
  assert.doesNotMatch(migration,/or v_repository in \(/);
  assert.doesNotMatch(migration,/or exists \([\s\S]*projectos_projects/);
});

test('explicit owner/repo actions route before model fallback without creating a project prerequisite', () => {
  assert.match(migration,/pandora_chat_universal_dispatch_v6/);
  assert.match(repositoryTargeting,/pandora_chat_universal_dispatch_v7/);
  assert.match(migration,/audit/);
  assert.match(migration,/inspect/);
  assert.match(migration,/review/);
  assert.match(migration,/check/);
  assert.match(migration,/pandora_chat_universal_dispatch_v5/);
  assert.match(migration,/jsonb_set\(v_result,'\{projectRequired\}','false'::jsonb,true\)/);
  assert.doesNotMatch(migration,/projectos_register_project|project\.create/);
});

test('mobile uses v6 and hides the internal ProjectOS inbox from user project context', () => {
  assert.match(api,/pandora_chat_universal_dispatch_v7/);
  assert.match(api,/neq\('project_key', 'projectos-inbox'\)/);
});

test('mobile handoffs stay in Universal Chat, never create a Project implicitly, and never submit the admission twice', () => {
  assert.doesNotMatch(screen,/handoffProjectId == null \|\| handoffProjectId\.isEmpty/);
  assert.doesNotMatch(screen,/initialIntent: handoff\.request/);
  assert.doesNotMatch(screen,/message: handoff\.request/);
  assert.doesNotMatch(screen,/intelligence-handoff/);
  assert.match(screen,/already performed the governed dispatch/);
});

test('model fallback is forbidden from manufacturing a Project prerequisite for existing targets', () => {
  assert.match(intelligence,/Never use project\.create as a prerequisite for reading, auditing, reviewing, fixing, deploying/);
  assert.match(intelligence,/Only classify create_project when the owner explicitly asks to create a new persistent Project or a new system/);
});
