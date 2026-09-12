
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const shellPath = new URL(
  '../apps/pandora-mobile/lib/app/pandora_chat_shell.dart',
  import.meta.url,
);
const pluginsPath = new URL(
  '../apps/pandora-mobile/lib/features/plugins/plugins_screen.dart',
  import.meta.url,
);

test('mobile drawer exposes Connections as the owner-facing plugin destination', async () => {
  const shell = await readFile(shellPath, 'utf8');

  assert.match(shell, /_ChatDestination\(\s*'Connections'/);
  assert.match(shell, /PluginsScreen\(\)/);
  assert.match(shell, /5 => 'plugins'/);
});

test('Plugins UI derives installed state from runtime connection truth', async () => {
  const plugins = await readFile(pluginsPath, 'utf8');

  assert.match(plugins, /repository\.connections\(allowCached: true\)/);
  assert.match(plugins, /deduplicateConnections\(raw\)/);
  assert.match(plugins, /resolveOwnerConnectionState\(connection\)/);
  assert.match(plugins, /OwnerConnectionState\.verified/);
  assert.match(plugins, /connection\.canRead \|\| connection\.canChange/);
  assert.match(plugins, /runtime\.map\(_PluginViewModel\.fromRuntime\)/);
  assert.match(plugins, /provider\.installed/);
  assert.match(plugins, /Search plugins/);
  assert.match(plugins, /'Installed'/);
  assert.match(plugins, /label: 'Public'/);
  assert.match(plugins, /label: 'Personal'/);
  assert.match(
    plugins,
    /Availability comes from Pandora runtime truth, not a hard-coded connected list\./,
  );
  assert.doesNotMatch(plugins, /Github\s*:\s*true|GitHub\s*:\s*true/);
});

test('Plugins UI fails closed when authorization is not verified', async () => {
  const plugins = await readFile(pluginsPath, 'utf8');

  assert.match(plugins, /Verified authorization is required before Pandora can use this plugin/);
  assert.match(plugins, /Live plugin runtime detail is not verified/);
  assert.match(plugins, /No verified plugins are connected right now/);
});
