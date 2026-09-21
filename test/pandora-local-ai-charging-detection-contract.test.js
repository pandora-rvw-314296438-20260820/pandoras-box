import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = fs.readFileSync(
  'apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraLocalAiChannel.kt',
  'utf8',
);

test('local AI charging detection cross-checks sticky Android battery state', () => {
  assert.match(source, /IntentFilter\(Intent\.ACTION_BATTERY_CHANGED\)/);
  assert.match(source, /BatteryManager\.EXTRA_STATUS/);
  assert.match(source, /BatteryManager\.EXTRA_PLUGGED/);
  assert.match(source, /BATTERY_STATUS_CHARGING/);
  assert.match(source, /BATTERY_STATUS_FULL/);
  assert.match(source, /batteryManager\.isCharging/);
  assert.match(
    source,
    /val charging = chargingByManager \|\| chargingByStatus \|\| batteryPlugged != 0/,
  );
});

test('local AI diagnostics expose how charging was detected', () => {
  assert.match(source, /"charging" to charging/);
  assert.match(source, /"chargingSource" to chargingSource/);
  assert.match(source, /"batteryPlugged" to pluggedSource/);
});
