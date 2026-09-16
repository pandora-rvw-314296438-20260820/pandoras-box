import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const machinePath = new URL(
  "../docs/security/pandora-device-permission-broker-v1.json",
  import.meta.url
);
const documentPath = new URL(
  "../docs/security/PANDORA_DEVICE_PERMISSION_BROKER_V1.md",
  import.meta.url
);
const [machineRaw, document] = await Promise.all([
  readFile(machinePath, "utf8"),
  readFile(documentPath, "utf8")
]);
const contract = JSON.parse(machineRaw);

test("M7-006 freezes trusted Android runtime readback as permission authority", () => {
  assert.equal(contract.schemaVersion, "pandora-device-permission-broker-v1");
  assert.equal(contract.trustedStateSource, "android_os_runtime_readback_only");
  assert.equal(contract.runtimePermission.freshStateRequired, true);
  assert.equal(contract.runtimePermission.cachedGrantAccepted, false);
  assert.match(document, /re-read trusted Android runtime state/i);
});

test("runtime permission prompts remain visible and user initiated", () => {
  assert.equal(contract.runtimePermission.userInitiatedPromptOnly, true);
  assert.equal(contract.runtimePermission.backgroundPromptAllowed, false);
  assert.match(document, /Background permission prompts are forbidden/i);
});

test("revocation remains user controlled and is rechecked before use", () => {
  assert.equal(contract.runtimePermission.revocationControlSurface, "app_details");
  assert.equal(contract.runtimePermission.recheckBeforeEveryUse, true);
  assert.match(document, /Revocation takes effect on the next capability evaluation/i);
});

test("roles and Device Owner cannot be silently or falsely acquired", () => {
  assert.equal(contract.androidRole.userControlled, true);
  assert.equal(contract.androidRole.silentRoleAcquisitionAllowed, false);
  assert.equal(contract.deviceOwner.mustBeActuallyProvisioned, true);
  assert.equal(contract.deviceOwner.policyMayNotPretendProvisioning, true);
});

test("forbidden shortcuts include silent grant regrant and retry loops", () => {
  for (const item of [
    "silent_permission_grant",
    "automatic_regrant_after_revocation",
    "broad_permission_pregrant",
    "permission_state_from_model_or_client",
    "background_permission_prompt",
    "permission_retry_loop"
  ]) {
    assert.ok(contract.forbidden.includes(item), item);
  }
});

test("CI contract does not claim Android runtime or physical completion", () => {
  assert.match(contract.acceptanceBoundary, /runtime wiring/i);
  assert.match(contract.acceptanceBoundary, /Redmi permission grant/i);
  assert.match(document, /CI cannot substitute for that physical evidence/i);
  assert.match(document, /avoids MainActivity\.kt/i);
});
