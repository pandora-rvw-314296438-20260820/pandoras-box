"use strict";

const { createHash, timingSafeEqual } = require("node:crypto");

const TOOL_DECISIONS = Object.freeze({
  ALLOW: "ALLOW",
  DENY: "DENY",
  REQUIRE_APPROVAL: "REQUIRE_APPROVAL",
  DEFER: "DEFER",
});

const RISK_LEVELS = Object.freeze({
  LOW: "LOW",
  MEDIUM: "MEDIUM",
  HIGH: "HIGH",
  CRITICAL: "CRITICAL",
});

const RETRY_MODES = Object.freeze({
  SAFE_RETRY: "SAFE_RETRY",
  IDEMPOTENT_RETRY: "IDEMPOTENT_RETRY",
  NO_AUTOMATIC_RETRY: "NO_AUTOMATIC_RETRY",
});

const IDEMPOTENCY_MODES = Object.freeze({
  NONE: "NONE",
  OPTIONAL: "OPTIONAL",
  REQUIRED: "REQUIRED",
});

const SIDE_EFFECTS = Object.freeze({
  NONE: "NONE",
  READ: "READ",
  PROJECT_MUTATION: "PROJECT_MUTATION",
  EXTERNAL_MUTATION: "EXTERNAL_MUTATION",
  PRODUCTION_MUTATION: "PRODUCTION_MUTATION",
});

const APPROVAL_MODES = Object.freeze({
  NONE: "NONE",
  POLICY: "POLICY",
  REQUIRED: "REQUIRED",
});

const ERROR_CLASSES = Object.freeze([
  "authorization",
  "rate_limit",
  "timeout",
  "network",
  "conflict",
  "invalid_request",
  "provider_unavailable",
  "resource_missing",
  "budget",
  "policy_denied",
  "approval_required",
  "verification_required",
  "ambiguous_mutation",
  "internal",
]);

function normalizeJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("Non-finite numbers are not allowed");
    return value;
  }
  if (Array.isArray(value)) return value.map(normalizeJson);
  if (typeof value === "object") {
    const proto = Object.getPrototypeOf(value);
    if (proto !== Object.prototype && proto !== null) throw new Error("Only plain JSON objects are allowed");
    const result = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== undefined) result[key] = normalizeJson(value[key]);
    }
    return result;
  }
  throw new Error(`Unsupported JSON value: ${typeof value}`);
}

function canonicalizeJson(value) {
  return JSON.stringify(normalizeJson(value));
}

function sha256Hex(value) {
  return createHash("sha256").update(typeof value === "string" ? value : canonicalizeJson(value), "utf8").digest("hex");
}

function computeActionHash({ tool, version, arguments: args, organization_id, project_id, environment, target_resource = null, project_version = null, policy_version }) {
  return sha256Hex({
    tool,
    version,
    arguments: args,
    organization_id,
    project_id,
    environment,
    target_resource,
    project_version,
    policy_version,
  });
}

function secureEqualHex(left, right) {
  if (!/^[0-9a-f]{64}$/.test(left || "") || !/^[0-9a-f]{64}$/.test(right || "")) return false;
  const a = Buffer.from(left, "hex");
  const b = Buffer.from(right, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}

module.exports = {
  TOOL_DECISIONS,
  RISK_LEVELS,
  RETRY_MODES,
  IDEMPOTENCY_MODES,
  SIDE_EFFECTS,
  APPROVAL_MODES,
  ERROR_CLASSES,
  canonicalizeJson,
  sha256Hex,
  computeActionHash,
  secureEqualHex,
};
