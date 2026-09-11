const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migrationPath = join(
  root,
  'supabase',
  'migrations',
  '20260911114500_pandora_plugin_runtime_registry_v3.sql',
);
const apiPath = join(
  root,
  'apps',
  'pandora-mobile',
  'lib',
  'core',
  'data',
  'pandora_intelligence_api.dart',
);
const pluginsPath = join(
  root,
  'apps',
  'pandora-mobile',
  'lib',
  'features',
  'plugins',
  'plugins_screen.dart',
);

const migration = await readFile(migrationPath, 'utf8');
const api = await readFile(apiPath, 'utf8');
const plugins = await readFile(pluginsPath, 'utf8');

test('plugin registry v3 enriches runtime truth without inventing identity', () => {
  assert.match(migration, /pandora_plugin_runtime_registry_v3/);
  assert.match(migration, /pandora_chat_capability_registry_v2/);
  assert.match(migration, /'account'/);
  assert.match(migration, /'verified', false/);
  assert.match(migration, /'scopesVerified', false/);
  assert.match(migration, /'actions'/);
  assert.match(migration, /'health'/);
  assert.match(migration, /'failure'/);
  assert.match(migration, /'lastVerifiedAt'/);
  assert.match(migration, /'projectRequired',false/);
  assert.match(migration, /grant execute on function public\.pandora_plugin_runtime_registry_v3\(uuid\) to authenticated/);
  assert.match(migration, /revoke all on function public\.pandora_plugin_runtime_registry_v3\(uuid\) from public, anon/);
});

test('mobile capability client reads the runtime registry directly', () => {
  assert.match(api, /Future<PandoraCapabilityRegistry> capabilityRegistry\(\)/);
  assert.match(api, /pandora_plugin_runtime_registry_v3/);
  assert.match(api, /class PandoraCapabilityRegistry/);
  assert.match(api, /class PandoraCapabilityProvider/);
  assert.match(api, /class PandoraCapabilityAction/);
  assert.match(api, /bool get installed => state == 'Connected' && canUseNow/);
  assert.match(api, /accountVerified/);
  assert.match(api, /scopesVerified/);
  assert.match(api, /failureMessage/);
});

test('Plugins UX exposes real runtime detail and governed lifecycle actions', () => {
  assert.match(plugins, /_loadRuntimeRegistry/);
  assert.match(plugins, /registry\.providers/);
  assert.match(plugins, /'Needs You'/);
  assert.match(plugins, /'Account'/);
  assert.match(plugins, /'Health'/);
  assert.match(plugins, /'Last verification'/);
  assert.match(plugins, /'Scopes'/);
  assert.match(plugins, /'Capabilities'/);
  assert.match(plugins, /'Reconnect'/);
  assert.match(plugins, /'Disconnect'/);
  assert.match(plugins, /ProjectOS authorization/);
  assert.match(plugins, /Do not claim this plugin is connected until provider readback verifies it/);
  assert.doesNotMatch(plugins, /hard-coded connected list[^.]*connected/i);
});
