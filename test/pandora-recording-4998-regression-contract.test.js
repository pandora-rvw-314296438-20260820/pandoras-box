import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const analysis = await readFile(
  'supabase/migrations/20260913040000_pandora_repository_analysis_execution_v1.sql',
  'utf8',
);
const visibility = await readFile(
  'supabase/migrations/20260913041000_pandora_owner_project_visibility_v1.sql',
  'utf8',
);
const shell = await readFile(
  'apps/pandora-mobile/lib/app/pandora_chat_shell.dart',
  'utf8',
);
const ownerApi = await readFile(
  'supabase/functions/pandora-owner-api/index.ts',
  'utf8',
);
const intelligence = await readFile(
  'supabase/functions/pandora-intelligence-chat/index.ts',
  'utf8',
);

test('recording 4998: full audit/analyze is ProjectOS research, never terminal repo metadata', () => {
  assert.match(analysis, /v_deep_analysis/);
  assert.match(analysis, /pandora_governed_repository_analysis_request_v1/);
  assert.match(analysis, /'github','repository\.read'/);
  assert.match(analysis, /projectos_accept_intake/);
  assert.match(analysis, /'research'/);
  assert.match(analysis, /'action','repository\.analyze'/);
  assert.match(analysis, /'verifiedComplete',false/);
  assert.match(analysis, /repository lookup is only preflight evidence/i);
  assert.match(analysis, /Build Theatre may project only real persisted/);
});

test('recording 4998: bounded status reads stay direct but audit/analyze takes deep path first', () => {
  const deep = analysis.indexOf('if v_deep_analysis and v_repository is not null then');
  const bounded = analysis.indexOf('if v_read_only and v_repository is not null then');
  assert.ok(deep >= 0);
  assert.ok(bounded > deep);
  assert.match(analysis, /audit\|analy\[sz\]e/);
});

test('recording 4998: search sheet owns controller lifetime and opens selected chat only after teardown', () => {
  assert.doesNotMatch(shell, /_workspaceKey/);
  assert.doesNotMatch(shell, /key:\s*_workspaceKey/);
  assert.match(shell, /showModalBottomSheet<PandoraIntelligenceThread>/);
  assert.match(shell, /_SearchChatsSheet\(threads: _threads\)/);
  assert.match(shell, /final TextEditingController _controller = TextEditingController\(\);/);
  assert.match(shell, /void dispose\(\) \{[\s\S]*?_controller\.dispose\(\);[\s\S]*?super\.dispose\(\);/);
  assert.match(shell, /pandora-search-chats-sheet/);
  assert.match(shell, /Navigator\.of\(context\)\.pop\(thread\)/);
  assert.match(shell, /if \(!mounted \|\| selected == null\) return;/);
  assert.match(shell, /await _openThread\(selected\)/);
  const searchStart = shell.indexOf('Future<void> _searchChats() async');
  const openThreadStart = shell.indexOf('Future<void> _openThread(', searchStart);
  const searchBody = shell.slice(searchStart, openThreadStart);
  assert.doesNotMatch(searchBody, /TextEditingController/);
  assert.doesNotMatch(searchBody, /\.dispose\(\)/);
});

test('recording 4998: owner shell is deterministically Graphite', () => {
  assert.match(shell, /PandoraPalette\.graphite/);
  assert.match(shell, /extensions: const <ThemeExtension<dynamic>>\[PandoraPalette\.graphite\]/);
});

test('recording 4998: internal ProjectOS rows are excluded from owner project summaries', () => {
  assert.match(ownerApi, /function ownerVisibleProject/);
  assert.match(ownerApi, /config\.ownerVisible === false/);
  assert.match(ownerApi, /pandora_control_plane/);
  assert.match(ownerApi, /\.filter\(ownerVisibleProject\)/);
  assert.match(ownerApi, /updated_at, config/);
  assert.match(visibility, /'ownerVisible',false/);
  assert.match(visibility, /projectos-inbox/);
  assert.match(visibility, /worker-\[a-z0-9-\]\*proof/);
});

test('recording 4998: ordinary model chat degrades trusted context without granting authority', () => {
  assert.match(intelligence, /async function trustedOptional/);
  assert.match(intelligence, /\["BACKEND_READ_FAILED","TRUSTED_CONTEXT_INVALID"\]\.includes\(code\)/);
  assert.match(intelligence, /execution:"worker_c_only"/);
  assert.match(intelligence, /modelMayProposeOnly:true/);
  assert.match(intelligence, /credentialsAvailableToModel:false/);
  assert.match(intelligence, /trustedContextState:tctx\.degraded===true\?"degraded":"verified"/);
});
