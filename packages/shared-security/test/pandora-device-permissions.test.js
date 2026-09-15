const assert = require("node:assert/strict");
const test = require("node:test");
const permission = require("../src/pandora-device-permissions.js");

const base = {
  capabilityId: "sensor.camera",
  trustedRuntimeState: true,
  policyAllowsCapability: true,
  implementationAvailable: true
};

test("M7-006 public-app authority needs no extra Android permission", () => {
  const result = permission.evaluateDevicePermissionGate({
    ...base,
    capabilityId: "files.scoped_access",
    authority: "public_app"
  });
  assert.equal(result.decision, "allow");
  assert.equal(result.cachedGrantAccepted, false);
  assert.equal(result.mustRecheckBeforeUse, true);
});

test("M7-006 untrusted runtime state fails closed even when a grant is asserted", () => {
  const result = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    trustedRuntimeState: false,
    permissionStateFresh: true,
    manifestDeclared: true,
    permissionGranted: true
  });
  assert.equal(result.decision, "deny");
  assert.equal(result.reasonCode, "permission_state_untrusted");
});

test("M7-006 denied and development-only authorities cannot execute", () => {
  for (const authority of ["policy_denied", "development_only"]) {
    const result = permission.evaluateDevicePermissionGate({
      ...base,
      authority
    });
    assert.equal(result.decision, "deny", authority);
  }
});

test("M7-006 runtime permissions must be declared and freshly read", () => {
  const undeclared = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    permissionStateFresh: true,
    manifestDeclared: false,
    permissionGranted: false
  });
  assert.equal(undeclared.reasonCode, "runtime_permission_not_declared");

  const stale = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    permissionStateFresh: false,
    manifestDeclared: true,
    permissionGranted: true
  });
  assert.equal(stale.reasonCode, "runtime_permission_state_not_fresh");
});

test("M7-006 a missing runtime permission becomes visible user action, never silent retry", () => {
  const result = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    permissionStateFresh: true,
    manifestDeclared: true,
    permissionGranted: false,
    userInitiatedPermissionRequest: false,
    permissionPromptAvailable: true
  });
  assert.equal(result.decision, "needs_user_action");
  assert.equal(result.permissionPromptAllowed, false);
  assert.equal(result.userActionSurface, "app_details");
  assert.equal(result.automaticRetryAllowed, false);
  assert.equal(result.revocationControlSurface, "app_details");
});

test("M7-006 a visible current user request may use the Android permission dialog", () => {
  const result = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    permissionStateFresh: true,
    manifestDeclared: true,
    permissionGranted: false,
    userInitiatedPermissionRequest: true,
    permissionPromptAvailable: true
  });
  assert.equal(result.decision, "needs_user_action");
  assert.equal(result.permissionPromptAllowed, true);
  assert.equal(result.userActionSurface, "runtime_permission_dialog");
});

test("M7-006 current Android grant allows use while preserving revocation control", () => {
  const result = permission.evaluateDevicePermissionGate({
    ...base,
    authority: "runtime_permission",
    permissionStateFresh: true,
    manifestDeclared: true,
    permissionGranted: true
  });
  assert.equal(result.decision, "allow");
  assert.equal(result.reasonCode, "runtime_permission_granted");
  assert.equal(result.revocationControlSurface, "app_details");
});

test("M7-006 Android roles are fresh, user-controlled boundaries", () => {
  const needsRole = permission.evaluateDevicePermissionGate({
    ...base,
    capabilityId: "phone.sms_role",
    authority: "android_role",
    roleStateFresh: true,
    roleAvailable: true,
    roleHeld: false
  });
  assert.equal(needsRole.decision, "needs_user_action");
  assert.equal(needsRole.userActionSurface, "android_role_settings");

  const allowed = permission.evaluateDevicePermissionGate({
    ...base,
    capabilityId: "phone.sms_role",
    authority: "android_role",
    roleStateFresh: true,
    roleAvailable: true,
    roleHeld: true
  });
  assert.equal(allowed.decision, "allow");
});

test("M7-006 Device Owner is never assumed from policy or cached state", () => {
  const denied = permission.evaluateDevicePermissionGate({
    ...base,
    capabilityId: "device.owner_control",
    authority: "device_owner",
    deviceOwnerStateFresh: true,
    deviceOwnerProvisioned: false
  });
  assert.equal(denied.reasonCode, "device_owner_not_provisioned");

  const stale = permission.evaluateDevicePermissionGate({
    ...base,
    capabilityId: "device.owner_control",
    authority: "device_owner",
    deviceOwnerStateFresh: false,
    deviceOwnerProvisioned: true
  });
  assert.equal(stale.reasonCode, "device_owner_state_not_fresh");
});

test("M7-006 implementation availability and policy authorization both fail closed", () => {
  assert.equal(permission.evaluateDevicePermissionGate({
    ...base,
    authority: "public_app",
   implementationAvailable: false
  }).reasonCode, "capability_not_implemented");

  assert.equal(permission.evaluateDevicePermissionGate({
    ...base,
    authority: "public_app",
    policyAllowsCapability: false
  }).reasonCode, "capability_not_authorized");
});

test("M7-006 Needs You projection is emitted only for a real Android user boundary", () => {
  const needs = permission.permissionDecisionNeedsYou(
    permission.evaluateDevicePermissionGate({
      ...base,
      authority: "runtime_permission",
      permissionStateFresh: true,
      manifestDeclared: true,
      permissionGranted: false
    })
  );
  assert.equal(needs.state, "needs_you");
  assert.equal(needs.retryAfterUserAction, true);
  assert.equal(needs.automaticRetryAllowed, false);

  const denied = permission.permissionDecisionNeedsYou(
    permission.evaluateDevicePermissionGate({
      ...base,
      authority: "policy_denied"
    })
  );
  assert.equal(denied, null);
});

test("M7-006 package root declarations export the permission broker APIs", () => {
  const { readFileSync } = require("node:fs");
  const { join } = require("node:path");
  const declarations = readFileSync(join(__dirname, "../dist/index.d.ts"), "utf8");
  const exported = declarations.match(/export \{([^}]+)\};/)?.[1]
    .split(",").map((name) => name.trim()) ?? [];
  for (const symbol of [
    "PERMISSION_GATE_SCHEMA_VERSION",
    "PERMISSION_AUTHORITY_MODES",
    "PERMISSION_GATE_DECISIONS",
    "evaluateDevicePermissionGate",
    "permissionDecisionNeedsYou"
  ]) {
    assert.ok(exported.includes(symbol), symbol);
  }
});
