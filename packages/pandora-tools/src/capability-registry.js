"use strict";

const { RISK_LEVELS, SIDE_EFFECTS, APPROVAL_MODES } = require("./contracts");
const { listToolDefinitions } = require("./registry");

const CAPABILITY_KINDS = Object.freeze(["tool", "model", "device", "service", "cloud", "app"]);
const CAPABILITY_SCOPES = Object.freeze(["project", "device", "provider", "service", "cloud", "app"]);
const CAPABILITY_AVAILABILITY = Object.freeze([
  "available",
  "permission_required",
  "implementation_pending",
  "unsupported",
  "forbidden",
  "disabled",
]);
const CAPABILITY_AUTHORITIES = Object.freeze([
  "governed_policy",
  "public_app",
  "runtime_permission",
  "android_role",
  "device_owner",
  "development_only",
  "policy_denied",
  "provider_account",
]);

function asText(value, field) {
  if (typeof value !== "string" || !value.trim()) throw new TypeError(`${field} is required`);
  return value.trim();
}

function asStringArray(value, field) {
  if (value == null) return Object.freeze([]);
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  if (value.some((item) => typeof item !== "string")) throw new TypeError(`${field} must contain only strings`);
  const items = value.map((item) => asText(item, field));
  if (new Set(items).size !== items.length) throw new TypeError(`${field} must not contain duplicates`);
  return Object.freeze(items);
}

function oneOf(value, field, allowed) {
  const text = asText(String(value), field);
  if (!allowed.includes(text)) throw new TypeError(`${field} must be one of: ${allowed.join(", ")}`);
  return text;
}

function normalizeCapabilityDescriptor(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new TypeError("capability descriptor must be an object");
  const id = asText(input.id, "id");
  const version = input.version == null ? 1 : input.version;
  if (!Number.isInteger(version) || version <= 0) throw new TypeError("version must be a positive integer");
  const kind = oneOf(input.kind, "kind", CAPABILITY_KINDS);
  const scope = oneOf(input.scope, "scope", CAPABILITY_SCOPES);
  const availability = oneOf(input.availability, "availability", CAPABILITY_AVAILABILITY);
  const authority = oneOf(input.authority, "authority", CAPABILITY_AUTHORITIES);
  const risk = oneOf(input.risk ?? RISK_LEVELS.LOW, "risk", Object.values(RISK_LEVELS));
  const sideEffect = oneOf(input.sideEffect ?? SIDE_EFFECTS.READ, "sideEffect", Object.values(SIDE_EFFECTS));
  const approval = oneOf(input.approval ?? APPROVAL_MODES.NONE, "approval", Object.values(APPROVAL_MODES));
  const executionAdapter = input.executionAdapter == null ? null : asText(input.executionAdapter, "executionAdapter");
  const gatewayExecutable = input.gatewayExecutable === true;
  if (gatewayExecutable && !executionAdapter) throw new TypeError("gatewayExecutable capability requires executionAdapter");
  if (availability === "forbidden" && authority !== "policy_denied") throw new TypeError("forbidden capability must use policy_denied authority");
  if (availability !== "available" && gatewayExecutable) throw new TypeError("only available capabilities can be gatewayExecutable");
  return Object.freeze({
    id,
    version,
    key: `${id}@${version}`,
    kind,
    scope,
    description: asText(input.description, "description"),
    authority,
    declaredAvailability: availability,
    availability,
    risk,
    sideEffect,
    approval,
    actorCapabilities: asStringArray(input.actorCapabilities, "actorCapabilities"),
    platformPermissions: asStringArray(input.platformPermissions, "platformPermissions"),
    executionAdapter,
    declaredGatewayExecutable: gatewayExecutable,
    gatewayExecutable,
    source: asText(input.source, "source"),
    metadata: Object.freeze(input.metadata && typeof input.metadata === "object" && !Array.isArray(input.metadata) ? { ...input.metadata } : {}),
  });
}

class PandoraCapabilityRegistry {
  constructor() {
    this.entries = new Map();
  }

  register(input) {
    const descriptor = normalizeCapabilityDescriptor(input);
    if (this.entries.has(descriptor.key)) throw new Error(`capability already registered: ${descriptor.key}`);
    this.entries.set(descriptor.key, descriptor);
    return descriptor;
  }

  registerMany(inputs) {
    if (!Array.isArray(inputs)) throw new TypeError("capability declarations must be an array");
    const descriptors = inputs.map(normalizeCapabilityDescriptor);
    const keys = new Set();
    for (const descriptor of descriptors) {
      if (keys.has(descriptor.key) || this.entries.has(descriptor.key)) throw new Error(`capability already registered: ${descriptor.key}`);
      keys.add(descriptor.key);
    }
    for (const descriptor of descriptors) this.entries.set(descriptor.key, descriptor);
    return Object.freeze(descriptors);
  }

  get(id, version = 1) {
    return this.entries.get(`${id}@${version}`) ?? null;
  }

  list(filter = {}) {
    return [...this.entries.values()].filter((entry) => {
      if (filter.kind && entry.kind !== filter.kind) return false;
      if (filter.scope && entry.scope !== filter.scope) return false;
      if (filter.availability && entry.availability !== filter.availability) return false;
      if (filter.gatewayExecutable != null && entry.gatewayExecutable !== filter.gatewayExecutable) return false;
      if (filter.actorCapability && !entry.actorCapabilities.includes(filter.actorCapability)) return false;
      return true;
    });
  }

  applyRuntimeAvailability(id, availability, metadata = {}, version = 1) {
    const key = `${id}@${version}`;
    const current = this.entries.get(key);
    if (!current) throw new Error(`unknown capability: ${key}`);
    const nextAvailability = oneOf(availability, "availability", CAPABILITY_AVAILABILITY);
    const declaredAvailability = current.declaredAvailability ?? current.availability;
    const declaredGatewayExecutable = current.declaredGatewayExecutable === true;
    if (nextAvailability === "forbidden" && current.authority !== "policy_denied") {
      throw new TypeError("runtime state cannot convert non-policy-denied capability to forbidden");
    }
    if (nextAvailability === "available" && !["available", "permission_required"].includes(declaredAvailability)) {
      throw new TypeError("runtime state cannot promote capability beyond declared availability");
    }
    const next = Object.freeze({
      ...current,
      availability: nextAvailability,
      gatewayExecutable: declaredGatewayExecutable && nextAvailability === "available",
      metadata: Object.freeze({ ...current.metadata, runtime: Object.freeze({ ...metadata }) }),
    });
    this.entries.set(key, next);
    return next;
  }
}

function descriptorFromToolDefinition(definition) {
  return normalizeCapabilityDescriptor({
    id: `tool.${definition.name}`,
    version: definition.version,
    kind: "tool",
    scope: definition.resourceScope || "project",
    description: definition.description,
    authority: "governed_policy",
    availability: definition.runtimeAvailability || "available",
    risk: definition.defaultRisk,
    sideEffect: definition.sideEffect,
    approval: definition.approval,
    actorCapabilities: definition.capabilityRequirements,
    platformPermissions: definition.platformPermissions || [],
    executionAdapter: definition.executor,
    gatewayExecutable: (definition.resourceScope || "project") === "project" && (definition.runtimeAvailability || "available") === "available",
    source: "pandora-tool-registry",
    metadata: {
      toolName: definition.name,
      toolVersion: definition.version,
      retry: definition.retry,
      idempotency: definition.idempotency,
    },
  });
}

function descriptorFromModelDeclaration(model) {
  const boundary = String(model.executionBoundary || "external_provider");
  const scope = boundary === "device" ? "device" : boundary === "pandora_trusted_cloud" ? "cloud" : "provider";
  const provider = asText(model.provider, "model.provider");
  const modelId = asText(model.modelId, "model.modelId");
  return normalizeCapabilityDescriptor({
    id: `model.${provider}.${modelId}`,
    version: 1,
    kind: "model",
    scope,
    description: `Model capability declaration for ${provider}/${modelId}`,
    authority: boundary === "device" ? "governed_policy" : "provider_account",
    availability: model.enabled === false ? "disabled" : "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.NONE,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: [],
    platformPermissions: [],
    executionAdapter: `ModelAdapter:${provider}`,
    gatewayExecutable: false,
    source: "pandora-model-capability-registry",
    metadata: {
      provider,
      modelId,
      executionBoundary: boundary,
      capabilities: model.capabilities && typeof model.capabilities === "object" ? { ...model.capabilities } : {},
      outputModes: Array.isArray(model.outputModes) ? [...model.outputModes] : [],
    },
  });
}

function descriptorFromDeviceCapability(capability) {
  return normalizeCapabilityDescriptor({
    id: `device.capability.${asText(capability.id, "device capability id")}`,
    version: 1,
    kind: "device",
    scope: "device",
    description: asText(capability.reason, "device capability reason"),
    authority: oneOf(capability.authority, "device capability authority", CAPABILITY_AUTHORITIES),
    availability: oneOf(capability.availability, "device capability availability", CAPABILITY_AVAILABILITY),
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: null,
    gatewayExecutable: false,
    source: "pandora-device-agent-runtime",
    metadata: {
      deviceCapabilityId: capability.id,
      normalOperationDependency: capability.normalOperationDependency === true,
    },
  });
}

function registerProjectTools(registry) {
  return registry.registerMany(listToolDefinitions().map(descriptorFromToolDefinition));
}

function registerModels(registry, declarations) {
  if (!Array.isArray(declarations)) throw new TypeError("model declarations must be an array");
  return registry.registerMany(declarations.map(descriptorFromModelDeclaration));
}

function registerDeviceCapabilityManifest(registry, manifest) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) throw new TypeError("device manifest must be an object");
  if (!Array.isArray(manifest.capabilities)) throw new TypeError("device manifest capabilities must be an array");
  return registry.registerMany(manifest.capabilities.map(descriptorFromDeviceCapability));
}

const DEVICE_TOOL_CAPABILITIES = Object.freeze([
  Object.freeze({
    id: "tool.device.get_capability_manifest",
    version: 1,
    kind: "tool",
    scope: "device",
    description: "Read the live Device Agent capability manifest without inferring unavailable authority.",
    authority: "public_app",
    availability: "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: "DeviceAgentExecutor",
    gatewayExecutable: false,
    source: "pandora-device-agent-v1",
    metadata: { deviceMethod: "getCapabilityManifest", deviceCapability: "device.diagnostics.safe", executionOwner: "M3-005" },
  }),
  Object.freeze({
    id: "tool.device.get_permission_states",
    version: 1,
    kind: "tool",
    scope: "device",
    description: "Read declared/granted state for the Device Agent allowlisted Android permissions.",
    authority: "public_app",
    availability: "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: "DeviceAgentExecutor",
    gatewayExecutable: false,
    source: "pandora-device-agent-v1",
    metadata: { deviceMethod: "getPermissionStates", deviceCapability: "device.permission_state", executionOwner: "M3-005" },
  }),
  Object.freeze({
    id: "tool.device.run_safe_diagnostic",
    version: 1,
    kind: "tool",
    scope: "device",
    description: "Run only an allowlisted read-only Device Agent diagnostic kind.",
    authority: "public_app",
    availability: "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: "DeviceAgentExecutor",
    gatewayExecutable: false,
    source: "pandora-device-agent-v1",
    metadata: { allowedKinds: ["capability_manifest", "permission_state"], deviceCapability: "device.diagnostics.safe", executionOwner: "M3-005" },
  }),
  Object.freeze({
    id: "tool.device.get_resource_snapshot",
    version: 1,
    kind: "tool",
    scope: "device",
    description: "Read live CPU, RAM, storage, battery, thermal, process and network telemetry through the implemented M4-009 Android Device Agent runtime.",
    authority: "public_app",
    availability: "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: "DeviceAgentExecutor",
    gatewayExecutable: false,
    source: "pandora-device-agent-v1",
    metadata: { deviceCapability: "resource.introspection", implementationOwner: "M4-009", executionOwner: "M3-005", executionBoundary: "android_local_read" },
  }),
  Object.freeze({
    id: "tool.device.run_resource_benchmark",
    version: 1,
    kind: "tool",
    scope: "device",
    description: "Run the implemented M4-009 bounded safe local resource benchmark through the Android Device Agent runtime.",
    authority: "public_app",
    availability: "available",
    risk: RISK_LEVELS.LOW,
    sideEffect: SIDE_EFFECTS.READ,
    approval: APPROVAL_MODES.NONE,
    actorCapabilities: ["device.inspect"],
    platformPermissions: [],
    executionAdapter: "DeviceAgentExecutor",
    gatewayExecutable: false,
    source: "pandora-device-agent-v1",
    metadata: { deviceCapability: "resource.introspection", implementationOwner: "M4-009", executionOwner: "M3-005", executionBoundary: "android_local_read" },
  }),
]);

function registerDeviceTools(registry) {
  return registry.registerMany(DEVICE_TOOL_CAPABILITIES);
}

function createDefaultCapabilityRegistry() {
  const registry = new PandoraCapabilityRegistry();
  registerProjectTools(registry);
  registerDeviceTools(registry);
  return registry;
}

module.exports = {
  CAPABILITY_KINDS,
  CAPABILITY_SCOPES,
  CAPABILITY_AVAILABILITY,
  CAPABILITY_AUTHORITIES,
  DEVICE_TOOL_CAPABILITIES,
  PandoraCapabilityRegistry,
  normalizeCapabilityDescriptor,
  descriptorFromToolDefinition,
  descriptorFromModelDeclaration,
  descriptorFromDeviceCapability,
  registerProjectTools,
  registerModels,
  registerDeviceCapabilityManifest,
  registerDeviceTools,
  createDefaultCapabilityRegistry,
};
