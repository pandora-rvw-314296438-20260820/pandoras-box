"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../src");

test("default capability registry projects governed tool metadata without changing gateway authority", () => {
  const registry = T.createDefaultCapabilityRegistry();
  const readFile = registry.get("tool.read_file");
  assert.ok(readFile);
  assert.equal(readFile.kind, "tool");
  assert.equal(readFile.scope, "project");
  assert.equal(readFile.authority, "governed_policy");
  assert.equal(readFile.availability, "available");
  assert.equal(readFile.executionAdapter, "WorkspaceExecutor");
  assert.equal(readFile.gatewayExecutable, true);
  assert.deepEqual(readFile.actorCapabilities, ["workspace.files.read"]);
  assert.equal(readFile.sideEffect, T.SIDE_EFFECTS.READ);
});

test("device diagnostics are first-class discovery tools but fail closed until M3-005 binds device execution", () => {
  const registry = T.createDefaultCapabilityRegistry();
  const manifest = registry.get("tool.device.get_capability_manifest");
  const permissions = registry.get("tool.device.get_permission_states");
  const diagnostics = registry.get("tool.device.run_safe_diagnostic");

  for (const item of [manifest, permissions, diagnostics]) {
    assert.ok(item);
    assert.equal(item.kind, "tool");
    assert.equal(item.scope, "device");
    assert.equal(item.availability, "available");
    assert.equal(item.executionAdapter, "DeviceAgentExecutor");
    assert.equal(item.gatewayExecutable, false);
    assert.deepEqual(item.actorCapabilities, ["device.inspect"]);
  }
});

test("resource introspection and safe benchmarks remain truthful implementation-pending M4-009 capabilities", () => {
  const registry = T.createDefaultCapabilityRegistry();
  for (const id of ["tool.device.get_resource_snapshot", "tool.device.run_resource_benchmark"]) {
    const item = registry.get(id);
    assert.ok(item);
    assert.equal(item.scope, "device");
    assert.equal(item.availability, "implementation_pending");
    assert.equal(item.gatewayExecutable, false);
    assert.equal(item.metadata.implementationOwner, "M4-009");
  }
});

test("runtime availability can narrow or restore availability but cannot grant execution authority", () => {
  const registry = T.createDefaultCapabilityRegistry();
  const before = registry.get("tool.device.get_capability_manifest");
  assert.equal(before.gatewayExecutable, false);

  const narrowed = registry.applyRuntimeAvailability(
    "tool.device.get_capability_manifest",
    "unsupported",
    { reason: "device disconnected" },
  );
  assert.equal(narrowed.availability, "unsupported");
  assert.equal(narrowed.gatewayExecutable, false);
  assert.equal(narrowed.executionAdapter, "DeviceAgentExecutor");

  const restored = registry.applyRuntimeAvailability(
    "tool.device.get_capability_manifest",
    "available",
    { reason: "device reconnected" },
  );
  assert.equal(restored.availability, "available");
  assert.equal(restored.gatewayExecutable, false);
});

test("runtime narrowing restores declared project execution but cannot promote pending implementation", () => {
  const registry = T.createDefaultCapabilityRegistry();
  const initial = registry.get("tool.read_file");
  assert.equal(initial.gatewayExecutable, true);
  assert.equal(initial.declaredGatewayExecutable, true);

  const down = registry.applyRuntimeAvailability("tool.read_file", "unsupported", { reason: "workspace offline" });
  assert.equal(down.gatewayExecutable, false);
  const back = registry.applyRuntimeAvailability("tool.read_file", "available", { reason: "workspace online" });
  assert.equal(back.gatewayExecutable, true);

  assert.throws(
    () => registry.applyRuntimeAvailability("tool.device.get_resource_snapshot", "available", { reason: "unverified" }),
    /cannot promote capability beyond declared availability/,
  );
  assert.equal(registry.get("tool.device.get_resource_snapshot").availability, "implementation_pending");
});

test("bulk registration is atomic and malformed descriptor types fail closed", () => {
  assert.throws(
    () => T.normalizeCapabilityDescriptor({ id: "tool.bad-version", version: 0, kind: "tool", scope: "project", description: "bad", authority: "governed_policy", availability: "available", actorCapabilities: [], platformPermissions: [], executionAdapter: "XExecutor", gatewayExecutable: true, source: "test" }),
    /positive integer/,
  );
  assert.throws(
    () => T.normalizeCapabilityDescriptor({ id: "tool.bad-capability", kind: "tool", scope: "project", description: "bad", authority: "governed_policy", availability: "available", actorCapabilities: [1], platformPermissions: [], executionAdapter: "XExecutor", gatewayExecutable: true, source: "test" }),
    /only strings/,
  );
  const registry = new T.PandoraCapabilityRegistry();
  assert.throws(() => registry.registerMany([
    { id: "service.atomic", kind: "service", scope: "service", description: "one", authority: "provider_account", availability: "available", actorCapabilities: [], platformPermissions: [], executionAdapter: "OneExecutor", gatewayExecutable: false, source: "test" },
    { id: "service.atomic", kind: "service", scope: "service", description: "duplicate", authority: "provider_account", availability: "available", actorCapabilities: [], platformPermissions: [], executionAdapter: "TwoExecutor", gatewayExecutable: false, source: "test" },
  ]), /already registered/);
  assert.equal(registry.list().length, 0);
});

test("model declarations join the same discovery registry without becoming tools or tool authority", () => {
  const registry = new T.PandoraCapabilityRegistry();
  T.registerModels(registry, [{
    provider: "gemini",
    modelId: "gemini-test",
    enabled: true,
    executionBoundary: "external_provider",
    capabilities: { reasoning: true, toolCalling: true },
    outputModes: ["text", "structured"],
  }]);

  const model = registry.get("model.gemini.gemini-test");
  assert.ok(model);
  assert.equal(model.kind, "model");
  assert.equal(model.scope, "provider");
  assert.equal(model.authority, "provider_account");
  assert.equal(model.availability, "available");
  assert.equal(model.executionAdapter, "ModelAdapter:gemini");
  assert.equal(model.gatewayExecutable, false);
  assert.equal(model.metadata.capabilities.reasoning, true);
});

test("live Device Agent capability truth can be registered without converting prediction into permission", () => {
  const registry = new T.PandoraCapabilityRegistry();
  T.registerDeviceCapabilityManifest(registry, {
    capabilities: [
      {
        id: "device.permission_state",
        authority: "public_app",
        availability: "available",
        reason: "Reads only allowlisted permission grant state.",
        normalOperationDependency: true,
      },
      {
        id: "resource.introspection",
        authority: "public_app",
        availability: "implementation_pending",
        reason: "Owned by M4-009.",
        normalOperationDependency: false,
      },
      {
        id: "protected_apps.private_data",
        authority: "policy_denied",
        availability: "forbidden",
        reason: "Protected application private data is denied.",
        normalOperationDependency: false,
      },
    ],
  });

  assert.equal(registry.get("device.capability.device.permission_state").availability, "available");
  assert.equal(registry.get("device.capability.resource.introspection").availability, "implementation_pending");
  const protectedData = registry.get("device.capability.protected_apps.private_data");
  assert.equal(protectedData.availability, "forbidden");
  assert.equal(protectedData.authority, "policy_denied");
  assert.equal(protectedData.gatewayExecutable, false);
});

test("descriptor invariants fail closed on authority widening or duplicate registration", () => {
  assert.throws(
    () => T.normalizeCapabilityDescriptor({
      id: "tool.bad",
      kind: "tool",
      scope: "device",
      description: "bad",
      authority: "public_app",
      availability: "forbidden",
      risk: T.RISK_LEVELS.LOW,
      sideEffect: T.SIDE_EFFECTS.READ,
      approval: T.APPROVAL_MODES.NONE,
      actorCapabilities: [],
      platformPermissions: [],
      executionAdapter: "DeviceAgentExecutor",
      gatewayExecutable: false,
      source: "test",
    }),
    /policy_denied/,
  );

  const registry = new T.PandoraCapabilityRegistry();
  const entry = {
    id: "service.example.read",
    kind: "service",
    scope: "service",
    description: "Example",
    authority: "provider_account",
    availability: "available",
    risk: T.RISK_LEVELS.LOW,
    sideEffect: T.SIDE_EFFECTS.READ,
    approval: T.APPROVAL_MODES.NONE,
    actorCapabilities: ["service.read"],
    platformPermissions: [],
    executionAdapter: "ExampleExecutor",
    gatewayExecutable: false,
    source: "test",
  };
  registry.register(entry);
  assert.throws(() => registry.register(entry), /already registered/);
});
