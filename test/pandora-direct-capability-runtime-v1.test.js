'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase', 'migrations', '20260918023000_pandora_direct_capability_runtime_v1.sql'),
  'utf8',
);

test('active Pandora chat route has no ProjectOS intake or legacy fallback', () => {
  const routerStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_universal_dispatch_v9');
  assert.ok(routerStart >= 0);
  const router = migration.slice(routerStart, migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_activity_admit_event_v1'));
  assert.doesNotMatch(router, /projectos_accept_intake/i);
  assert.doesNotMatch(router, /v9_legacy_20260917/i);
  assert.doesNotMatch(router, /universal_dispatch_v8/i);
  assert.match(router, /pandora_native_intelligence/);
});

test('canonical Pandora source edits use a protected branch and PR with provider readback', () => {
  assert.match(migration, /private\.pandora_direct_box_code_edit_v1/);
  assert.match(migration, /chatgpt\/pandora-direct-/);
  assert.match(migration, /\/git\/refs/);
  assert.match(migration, /\/pulls/);
  assert.match(migration, /providerReadback/);
  assert.match(migration, /'verified',true/);
  assert.match(migration, /v_readback_pr/);
});

test('direct editor uses Vault-backed provider brokers without credential material in model input', () => {
  assert.match(migration, /pandora_integration_github_api_20260825/);
  assert.match(migration, /pandora_worker_b_gemini_request_20260829/);
  assert.match(migration, /credential_material_rejected/);
  assert.match(migration, /gemini-3\.1-pro-preview/);
});
