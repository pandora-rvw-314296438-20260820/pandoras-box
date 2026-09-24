const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(join(root, 'supabase/migrations/20260925063000_pandora_meta_native_capability_v1.sql'), 'utf8');
const intelligence = readFileSync(join(root, 'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart'), 'utf8');
const ask = readFileSync(join(root, 'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart'), 'utf8');
const plugins = readFileSync(join(root, 'apps/pandora-mobile/lib/features/plugins/plugins_screen.dart'), 'utf8');

test('Meta appears in the Pandora-native capability registry with read-only usable actions', () => {
  assert.match(migration, /'provider','meta','label','Meta'/);
  assert.match(migration, /pandora_meta_connection_v1/);
  assert.match(migration, /'name','pages\.read'/);
  assert.match(migration, /'name','ads\.read'/);
  assert.match(migration, /'name','ads\.manage','mode','write','available',false/);
});

test('Connect Meta is routed to the one-time OAuth prepare RPC and live connection readback', () => {
  assert.match(migration, /facebook/);
  assert.match(migration, /instagram/);
  assert.match(migration, /pandora_meta_oauth_prepare_v1/);
  assert.match(migration, /'authorization',v_meta/);
  assert.match(migration, /External changes remain approval-gated/);
  const dispatchStart = migration.indexOf('CREATE OR REPLACE FUNCTION public.pandora_chat_capability_dispatch_native_v1');
  const dispatch = migration.slice(dispatchStart);
  assert.doesNotMatch(dispatch, /vault\.decrypted_secrets/);
});

test('mobile opens only deterministic allowlisted provider OAuth URLs', () => {
  assert.match(intelligence, /providerReadback/);
  assert.match(intelligence, /authorizationUrl/);
  assert.match(intelligence, /www\.facebook\.com/);
  assert.match(intelligence, /accounts\.google\.com/);
  assert.match(intelligence, /uri\.scheme != 'https'/);
  assert.match(ask, /package:url_launcher\/url_launcher\.dart/);
  assert.match(ask, /LaunchMode\.externalApplication/);
  assert.match(ask, /turn\.authorizationUrl/);
});

test('Plugins describes Meta from runtime truth rather than a fake installed state', () => {
  assert.match(plugins, /'meta'\s*=>/);
  assert.match(plugins, /Facebook Pages, Meta ad accounts, campaigns, and performance insights/);
  assert.match(plugins, /runtime\.map\(_PluginViewModel\.fromRuntime\)/);
});
