import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const edgePath = new URL('../supabase/functions/pandora-intelligence-chat/index.ts', import.meta.url);
const migrationPath = new URL('../supabase/migrations/20260830104500_pandora_intelligence_chat_v1.sql', import.meta.url);
const mobilePath = new URL('../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', import.meta.url);

const [edge, migration, mobile] = await Promise.all([
  readFile(edgePath, 'utf8'),
  readFile(migrationPath, 'utf8'),
  readFile(mobilePath, 'utf8'),
]);

test('Ask Pandora uses the Vault-backed Worker B provider boundary', () => {
  assert.match(edge, /pandora_worker_b_gemini_request_20260829/);
  assert.doesNotMatch(edge, /generativelanguage\.googleapis\.com/);
  assert.doesNotMatch(edge, /Deno\.env\.get\(["'](?:GEMINI|GOOGLE).*KEY/i);
  assert.match(edge, /Gemini proposes|You may propose actions|never execute tools/i);
});

test('model output cannot directly become arbitrary tool execution', () => {
  for (const name of [
    'project.create',
    'project.inspect',
    'project.change',
    'project.build.request',
    'project.preview.request',
    'project.publish.request',
    'domain.search',
    'domain.attach',
  ]) {
    assert.match(edge, new RegExp(name.replaceAll('.', '\\.'), 'u'));
  }
  assert.match(edge, /kind:\s*["']governed_intake["']/);
  assert.match(edge, /actionable\.has\(v\.intent\)/);
  assert.doesNotMatch(edge, /service_role.*body|gemini_api_key.*body/i);
});

test('durable conversation history is owner-readable but service-written', () => {
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /created_by\s*=\s*auth\.uid\(\)/i);
  assert.match(migration, /revoke insert, update, delete[\s\S]*from anon, authenticated/i);
  assert.match(migration, /grant all[\s\S]*to service_role/i);
});

test('the APK calls Pandora intelligence and carries no provider secret contract', () => {
  assert.match(mobile, /functionName = 'pandora-intelligence-chat'/);
  assert.doesNotMatch(mobile, /gemini_api_key|x-goog-api-key|service[_-]?role/i);
});
