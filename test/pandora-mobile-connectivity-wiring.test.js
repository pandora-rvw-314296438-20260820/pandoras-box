"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const native = readFileSync(
  join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "PandoraConnectivityChannel.kt"),
  "utf8",
);
const activity = readFileSync(
  join(root, "apps", "pandora-mobile", "platform", "android", "app", "src", "main", "kotlin", "com", "banataosystems", "pandora_mobile", "MainActivity.kt"),
  "utf8",
);
const dart = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "device", "pandora_connectivity_runtime.dart"),
  "utf8",
);
const manifestTool = readFileSync(
  join(root, "apps", "pandora-mobile", "tool", "configure_validation_android.py"),
  "utf8",
);

test("connectivity state uses public non-identifying Android network capabilities", () => {
  for (const required of [
    "ConnectivityManager",
    "NET_CAPABILITY_INTERNET",
    "NET_CAPABILITY_VALIDATED",
    "NET_CAPABILITY_CAPTIVE_PORTAL",
    "TRANSPORT_WIFI",
    "TRANSPORT_CELLULAR",
    "TRANSPORT_BLUETOOTH",
    "TRANSPORT_USB",
  ]) {
    assert.ok(native.includes(required), `missing ${required}`);
  }
  for (const forbidden of ["WifiManager", "BluetoothAdapter", "TelephonyManager", "getLinkProperties"]) {
    assert.ok(!native.includes(forbidden), `must not use ${forbidden}`);
  }
});

test("connectivity changes are user-mediated settings handoffs only", () => {
  for (const required of [
    "Settings.Panel.ACTION_INTERNET_CONNECTIVITY",
    "Settings.Panel.ACTION_WIFI",
    "Settings.ACTION_BLUETOOTH_SETTINGS",
    '"userActionRequired" to true',
    '"silentMutation" to false',
  ]) {
    assert.ok(native.includes(required), `missing ${required}`);
  }
  for (const forbidden of ["ACTION_TETHER_SETTINGS", "android.settings.TETHER_SETTINGS", "setWifiEnabled", "startTethering", "setDataEnabled", ".enable()", ".disable()"]) {
    assert.ok(!native.includes(forbidden), `silent mutation path found: ${forbidden}`);
  }
  assert.match(activity, /PandoraConnectivityChannel\.install\(/);
});

test("connectivity runtime adds no dangerous permission or identifier surface", () => {
  assert.match(manifestTool, /android\.permission\.ACCESS_NETWORK_STATE/);
  for (const forbiddenPermission of [
    "ACCESS_FINE_LOCATION",
    "ACCESS_COARSE_LOCATION",
    "BLUETOOTH_CONNECT",
    "BLUETOOTH_SCAN",
    "CHANGE_WIFI_STATE",
    "WRITE_SETTINGS",
    "MODIFY_PHONE_STATE",
  ]) {
    assert.ok(
      !manifestTool.includes(`android.permission.${forbiddenPermission}`),
      `${forbiddenPermission} must not be generated`,
    );
  }
  assert.match(dart, /Connectivity state must not contain device or network identifiers/);
  assert.match(dart, /silentMutationAllowed/);
  assert.match(dart, /normalOperationRequiresDesktop/);
  assert.match(dart, /rootRequired/);
});
