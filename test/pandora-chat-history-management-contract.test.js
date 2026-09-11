const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const api = fs.readFileSync(path.join(root, 'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart'), 'utf8');
const shell = fs.readFileSync(path.join(root, 'apps/pandora-mobile/lib/app/pandora_chat_shell.dart'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260911161000_pandora_intelligence_thread_management_v1.sql'), 'utf8');

test('thread management RPC is owner and organization scoped', () => {
  assert.match(migration, /auth\.uid\(\)/);
  assert.match(migration, /m\.status = 'active'/);
  assert.match(migration, /t\.created_by = v_uid/);
  assert.match(migration, /for update/);
  assert.match(migration, /PROJECT_ORG_MISMATCH/);
  assert.match(migration, /grant execute .* authenticated/);
});

test('thread management supports rename archive restore delete and project association', () => {
  for (const action of ['rename', 'archive', 'restore', 'delete', 'associate_project']) {
    assert.match(migration, new RegExp(`v_action = '${action}'`));
  }
  assert.match(migration, /delete from public\.pandora_intelligence_threads/);
  assert.match(migration, /update public\.pandora_intelligence_messages[\s\S]*project_id = p_project_id/);
});

test('mobile intelligence API exposes bounded thread management methods', () => {
  assert.match(api, /Future<void> renameThread/);
  assert.match(api, /Future<void> archiveThread/);
  assert.match(api, /Future<void> restoreThread/);
  assert.match(api, /Future<void> deleteThread/);
  assert.match(api, /associateThreadWithProject/);
  assert.match(api, /pandora_intelligence_thread_manage_v1/);
});

test('chat shell exposes explicit owner controls and confirms destructive delete', () => {
  assert.match(shell, /Conversation options/);
  assert.match(shell, /Rename conversation/);
  assert.match(shell, /Move to project/);
  assert.match(shell, /Archive/);
  assert.match(shell, /Delete conversation\?/);
  assert.match(shell, /This cannot be undone/);
  assert.match(shell, /associateThreadWithProject/);
});
