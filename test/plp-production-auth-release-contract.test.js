import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = (path) => fs.readFileSync(path, 'utf8');

const mainPlp = read('apps/pandora-mobile/lib/main_plp.dart');
const storage = read(
  'apps/pandora-mobile/lib/core/security/mobile_auth_storage.dart',
);
const config = read('apps/pandora-mobile/lib/pandora_config.dart');
const settings = read(
  'apps/pandora-mobile/lib/features/settings/settings_screen.dart',
);

test('PLP dedicated-device sessions use OS encrypted storage', () => {
  assert.match(mainPlp, /PandoraSecureAuthStorage\(PandoraConfig\.supabaseUrl\)/);
  assert.doesNotMatch(mainPlp, /EmptyLocalStorage/);
  assert.match(storage, /class PandoraSecureAuthStorage extends LocalStorage/);
  assert.match(storage, /FlutterSecureStorage/);
  assert.match(storage, /storageNamespace: 'pandora_auth_v1'/);
  assert.match(storage, /migrateOnAlgorithmChange: true/);
  assert.match(storage, /clearLegacyPersistedSession/);
});

test('PLP production identity is an explicit build-time release gate', () => {
  assert.match(
    config,
    /bool\.fromEnvironment\(\s*'PANDORA_PRODUCTION_RELEASE'/,
  );
  assert.match(config, /defaultValue: false/);
  assert.match(config, /Production Release — Android release signed/);
  assert.match(config, /Owner Test — Android debug signed/);
  assert.match(settings, /PandoraConfig\.releaseStateLabel/);
});
