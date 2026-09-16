"use strict";

const { PandoraToolError } = require("./errors");

const SAFE_STEP_CONTEXT_KEYS = Object.freeze(["tool_call_id"]);

function snapshotValue(value, path = "context") {
  if (value === null || value === undefined) return value;
  if (["string", "boolean"].includes(typeof value)) return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new PandoraToolError("invalid_request", "TOOL_CONTEXT_VALUE_INVALID", `${path} must be finite`);
    }
    return value;
  }
  if (Array.isArray(value)) {
    return Object.freeze(value.map((item, index) => snapshotValue(item, `${path}[${index}]`)));
  }
  if (typeof value === "object") {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw new PandoraToolError("invalid_request", "TOOL_CONTEXT_VALUE_INVALID", `${path} must be plain data`);
    }
    const clone = {};
    for (const [key, nested] of Object.entries(value)) {
      clone[key] = snapshotValue(nested, `${path}.${key}`);
    }
    return Object.freeze(clone);
  }
  throw new PandoraToolError("invalid_request", "TOOL_CONTEXT_VALUE_INVALID", `${path} contains unsupported runtime state`);
}

function snapshotNetworkResolver(resolver) {
  if (resolver == null) return resolver;
  if (typeof resolver.resolve !== "function") {
    throw new PandoraToolError("invalid_request", "NETWORK_RESOLVER_INVALID", "Trusted network resolver must expose resolve()");
  }
  const resolve = resolver.resolve.bind(resolver);
  return Object.freeze({ resolve });
}

function snapshotToolContext(context = {}) {
  if (!context || typeof context !== "object" || Array.isArray(context)) {
    throw new PandoraToolError("invalid_request", "TOOL_CONTEXT_INVALID", "Tool context must be an object");
  }
  const snapshot = {};
  for (const [key, value] of Object.entries(context)) {
    snapshot[key] = key === "network_resolver"
      ? snapshotNetworkResolver(value)
      : snapshotValue(value, `context.${key}`);
  }
  return Object.freeze(snapshot);
}

function mergeStepContext(trustedContext, rawStepContext, index) {
  if (rawStepContext == null) return trustedContext;
  if (typeof rawStepContext !== "object" || Array.isArray(rawStepContext)) {
    throw new PandoraToolError("invalid_request", "TOOL_CHAIN_STEP_CONTEXT_INVALID", `Tool chain step ${index} context is invalid`);
  }
  const keys = Object.keys(rawStepContext);
  for (const key of keys) {
    if (!SAFE_STEP_CONTEXT_KEYS.includes(key)) {
      throw new PandoraToolError(
        "policy_denied",
        "TOOL_CHAIN_STEP_CONTEXT_FORBIDDEN",
        `Tool chain step ${index} cannot override trusted context field ${key}`,
      );
    }
  }
  if (keys.length === 0) return trustedContext;
  return Object.freeze({
    ...trustedContext,
    tool_call_id: snapshotValue(rawStepContext.tool_call_id, `step[${index}].context.tool_call_id`),
  });
}

module.exports = { snapshotToolContext, mergeStepContext };
