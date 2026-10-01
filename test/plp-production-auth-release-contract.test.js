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

test('PLP release identity stays non-production until external certification', () => {
  assert.match(config, /PANDORA_ARTIFACT_CLASS/);
  assert.match(config, /static const productionRelease = false/);
  assert.match(config, /Owner Test — Android debug signed/);
  assert.match(settings, /Not a production release/);
  assert.doesNotMatch(settings, /PandoraConfig\.releaseStateLabel/);
});
