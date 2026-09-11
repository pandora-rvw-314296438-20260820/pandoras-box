import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationPath = new URL('../supabase/migrations/20260911050500_pandora_chat_capability_loop_v1.sql', import.meta.url);
const mobilePath = new URL('../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', import.meta.url);

const migration = await readFile(migrationPath, 'utf8');
const mobile = await readFile(mobilePath, 'utf8');

test('capability registry comes from runtime truth instead of model claims', () => {
  assert.match(migration, /pandora_chat_capability_registry_v1/);
  assert.match(migration, /projectos_integration_health/);
  assert.match(migration, /Github_supabase/);
  assert.match(migration, /mcpmaster_supabase_account_1_pat/);
  assert.match(migration, /posthog_personal_api_key/);
  assert.match(migration, /Google Workspace authorization is required/);
  assert.doesNotMatch(migration, /pandora_posthog_project_token[^\n]*analytics\.query[^\n]*available[^\n]*true/);
});

test('provider reads are bounded and mutations remain ProjectOS governed', () => {
  assert.match(migration, /v_member_role not in \('owner','admin'\)/);
  assert.match(migration, /pandora_chat_repository_not_allowlisted/);
  assert.match(migration, /https:\/\/api\.github\.com\/repos\//);
  assert.match(migration, /https:\/\/api\.supabase\.com\/v1\/projects\//);
  assert.match(migration, /projectos_accept_intake/);
  assert.match(migration, /'pandora_chat'/);
  assert.match(migration, /provider readback and verification are still required/);
  assert.match(migration, /pandora_intelligence_messages/);
  assert.match(migration, /pandora_capability_gateway/);
});

test('mobile chat invokes the capability gateway and fails closed on capability lookup errors', () => {
  assert.match(mobile, /pandora_chat_universal_dispatch_v3/);
  assert.match(mobile, /if \(message\.trim\(\)\.isEmpty\) return null/);
  assert.match(mobile, /textAttachment == null && imageAttachment == null/);
  assert.match(mobile, /Pandora could not verify that capability right now/);
  assert.match(mobile, /if \(capabilityTurn != null\) return capabilityTurn/);
});
