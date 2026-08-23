"use strict";

Object.defineProperty(exports, "__esModule", { value: true });
exports.prepareProviderResult = prepareProviderResult;
exports.prepareToolPresentation = prepareToolPresentation;

const PROVIDER_LIMITS = Object.freeze({
  // Leaves deterministic headroom for MCP text + structured representations.
  maxBytes: 128 * 1024,
  maxArrayItems: 500,
  maxObjectKeys: 500,
  maxDepth: 20,
  maxNodes: 20_000,
  maxStringChars: 96 * 1024,
});
const PRESENTATION_LIMITS = Object.freeze({
  maxBytes: 512 * 1024,
  maxArrayItems: 500,
  maxObjectKeys: 500,
  maxDepth: 20,
  maxNodes: 20_000,
  maxStringChars: 256 * 1024,
});

function contractError(category, phase) {
  return Object.assign(
    new Error("Provider response contract is invalid or exceeds bounded ProjectOS limits"),
    {
      name: "ProviderResultContractError",
      status: 502,
      code: "provider_response_contract_error",
      category,
      phase,
    },
  );
}

function cloneValue(value, state, depth, limits, phase, presentation) {
  if (depth > limits.maxDepth) throw contractError("depth", phase);
  state.nodes += 1;
  if (state.nodes > limits.maxNodes) throw contractError("nodes", phase);
  if (value === null || typeof value === "boolean") return value;
  if (typeof value === "string") {
    if (value.length > limits.maxStringChars) throw contractError("string", phase);
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw contractError("serialization", phase);
    return value;
  }
  if (value === undefined && presentation) return null;
  if (!value || typeof value !== "object") throw contractError("serialization", phase);
  if (state.active.has(value)) throw contractError("cycle", phase);

  state.active.add(value);
  try {
    if (Array.isArray(value)) {
      if (value.length > limits.maxArrayItems) throw contractError("array_items", phase);
      const expected = new Set([
        "length",
        ...Array.from({ length: value.length }, (_, index) => String(index)),
      ]);
      if (Reflect.ownKeys(value).some((key) => typeof key !== "string" || !expected.has(key))) {
        throw contractError("array_shape", phase);
      }
      return value.map((_, index) => {
        const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
        if (!descriptor || !("value" in descriptor) || descriptor.enumerable !== true) {
          throw contractError("array_shape", phase);
        }
        return cloneValue(
          descriptor.value,
          state,
          depth + 1,
          limits,
          phase,
          presentation,
        );
      });
    }

    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw contractError("object_prototype", phase);
    }
    const keys = Reflect.ownKeys(value);
    if (keys.length > limits.maxObjectKeys || keys.some((key) => typeof key !== "string")) {
      throw contractError("object_shape", phase);
    }
    const output = {};
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor || !("value" in descriptor) || descriptor.enumerable !== true) {
        throw contractError("object_shape", phase);
      }
      if (descriptor.value === undefined && presentation) continue;
      output[key] = cloneValue(
        descriptor.value,
        state,
        depth + 1,
        limits,
        phase,
        presentation,
      );
    }
    return output;
  } finally {
    state.active.delete(value);
  }
}

function boundedClone(value, limits, phase, presentation) {
  const cloned = cloneValue(
    value,
    { nodes: 0, active: new Set() },
    0,
    limits,
    phase,
    presentation,
  );
  let text;
  try {
    text = JSON.stringify(cloned);
  } catch {
    throw contractError("serialization", phase);
  }
  if (typeof text !== "string" || Buffer.byteLength(text, "utf8") > limits.maxBytes) {
    throw contractError("bytes", phase);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw contractError("serialization", phase);
  }
}

function prepareProviderResult(value) {
  return boundedClone(value, PROVIDER_LIMITS, "provider_result", false);
}

function prepareToolPresentation(value) {
  return boundedClone(value, PRESENTATION_LIMITS, "tool_presentation", true);
}
