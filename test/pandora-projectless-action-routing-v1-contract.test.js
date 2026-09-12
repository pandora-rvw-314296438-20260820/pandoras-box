import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migration = await readFile('supabase/migrations/20260912082000_pandora_projectless_action_routing_v1.sql','utf8');
const api = await readFile('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart','utf8');
const screen = await readFile('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart','utf8');
const intelligence = await readFile('supabase/functions/pandora-intelligence-chat/index.ts','utf8');

test('explicit owner/repo actions route before model fallback without creating a project prerequisite', () => {
  assert.match(migration,/pandora_chat_universal_dispatch_v6/);
  assert.match(migration,/audit\|inspect\|review\|check/);
  assert.match(migration,/pandora_chat_universal_dispatch_v5/);
  assert.match(migration,/'projectRequired','false'::jsonb/);
  assert.doesNotMatch(migration,/projectos_register_project|project\.create/);
});

test('mobile uses v6 and hides the internal ProjectOS inbox from user project context', () => {
  assert.match(api,/pandora_chat_universal_dispatch_v6/);
  assert.match(api,/neq\('project_key', 'projectos-inbox'\)/);
});

test('a missing handoff project id creates a Project only for explicit create_project intent', () => {
  assert.match(screen,/turn\.intent == 'create_project'[\s\S]*handoffProjectId == null/);
  assert.match(screen,/dependencies\.repository\.ask\([\s\S]*projectId: handoff\.projectId/);
});

test('model fallback is forbidden from manufacturing a Project prerequisite for existing targets', () => {
  assert.match(intelligence,/Never use project\.create as a prerequisite for reading, auditing, reviewing, fixing, deploying/);
  assert.match(intelligence,/Only classify create_project when the owner explicitly asks to create a new persistent Project or a new system/);
});
