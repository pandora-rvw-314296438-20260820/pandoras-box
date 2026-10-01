import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const main = readFileSync('apps/pandora-mobile/lib/main_plp.dart', 'utf8');
const storage = readFileSync(
  'apps/pandora-mobile/lib/core/security/plp_secure_auth_storage.dart',
  'utf8',
);
const manifestTool = readFileSync(
  'apps/pandora-mobile/tool/configure_validation_android.py',
  'utf8',
);
const settings = readFileSync(
  'apps/pandora-mobile/lib/features/enterprise/plp_editorial_surfaces.dart',
  'utf8',
);

test('PLP dedicated device persists auth only in secure storage', () => {
  assert.match(main, /PlpSecureAuthStorage/);
  assert.doesNotMatch(main, /localStorage:\s*EmptyLocalStorage/);
  assert.match(storage, /extends LocalStorage/);
  assert.match(storage, /FlutterSecureStorage/);
  assert.match(storage, /storageNamespace:\s*'pandora_plp_auth_v1'/);
  assert.match(storage, /persistSession\(/);
  assert.match(storage, /removePersistedSession\(/);
});

test('PLP still purges the legacy shared-preferences session key', () => {
  assert.match(main, /clearLegacyPersistedSession/);
});

test('PLP Android disables application backup for secure local state', () => {
  assert.match(manifestTool, /android:allowBackup="false"/);
});

test('PLP exposes explicit confirmed sign-out from settings', () => {
  assert.match(settings, /plp-settings-sign-out/);
  assert.match(settings, /plp-sign-out-confirm/);
  assert.match(settings, /Remove the encrypted PLP session/);
});
