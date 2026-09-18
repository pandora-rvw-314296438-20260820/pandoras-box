'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase', 'migrations', '20260918033800_pandora_native_capability_registry_v1.sql'),
  'utf8',
);

test('active universal router uses Pandora-native capability dispatch', () => {
  const start = migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_universal_dispatch_v9');
  assert.ok(start >= 0);
  const router = migration.slice(start, migration.indexOf('revoke all on function public.pandora_chat_universal_dispatch_v9'));
  assert.match(router, /pandora_chat_capability_dispatch_native_v1/);
  assert.match(router, /pandora_direct_box_code_edit_v1/);
  assert.doesNotMatch(router, /projectos/i);
});

test('native provider dispatcher has live GitHub Supabase Vercel and Google paths', () => {
  const start = migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_capability_dispatch_native_v1');
  assert.ok(start >= 0);
  const native = migration.slice(start, migration.indexOf('revoke all on function public.pandora_chat_capability_dispatch_native_v1'));
  assert.match(native, /pandora_integration_github_api_20260825/);
  assert.match(native, /api\.supabase\.com\/v1\/projects/);
  assert.match(native, /pandora_worker_f_vercel_api_20260829/);
  assert.match(native, /pandora_google_workspace_connection_v1/);
  assert.match(native, /providerReadback/);
  assert.doesNotMatch(native, /projectos/i);
});

test('native capability registry exposes honest availability without ProjectOS', () => {
  const start = migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_capability_registry_v3');
  assert.ok(start >= 0);
  const registry = migration.slice(start, migration.indexOf('revoke all on function public.pandora_chat_capability_registry_v3'));
  assert.match(registry, /GitHub/);
  assert.match(registry, /Supabase/);
  assert.match(registry, /Vercel/);
  assert.match(registry, /PostHog/);
  assert.match(registry, /Google Workspace/);
  assert.match(registry, /projectRequired/);
  assert.doesNotMatch(registry, /projectos/i);
});

test('legacy provider-health storage is hidden behind Pandora-native view', () => {
  assert.match(migration, /create or replace view public\.pandora_provider_health/i);
  const refs = migration.match(/projectos_integration_health/gi) || [];
  assert.equal(refs.length, 1);
});
