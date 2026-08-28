"use strict";

const { domainToASCII } = require("node:url");
const { PandoraToolError } = require("./errors");
const { validateProjectPath } = require("./path-safety");
const { getToolDefinition } = require("./registry");

const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const IDEMPOTENCY_RE = /^[A-Za-z0-9][A-Za-z0-9._:/-]{7,199}$/;
const ARTIFACT_RE = /^artifact:\/\/[A-Za-z0-9][A-Za-z0-9._:/-]{1,287}$/;

function fail(code, message, details) {
  throw new PandoraToolError("invalid_request", code, message, details);
}

function normalizeDomain(value) {
  if (typeof value !== "string") fail("DOMAIN_INVALID", "Domain must be a string");
  let hostname = value.trim().replace(/\.$/, "").toLowerCase();
  if (!hostname || hostname.includes("://") || hostname.includes("/") || hostname.includes(":") || hostname.includes("@") || hostname.startsWith("*.")) {
    fail("DOMAIN_INVALID", "Domain must be a bare canonical hostname");
  }
  hostname = domainToASCII(hostname);
  if (!hostname || hostname.length > 253) fail("DOMAIN_INVALID", "Domain cannot be normalized safely");
  const labels = hostname.split(".");
  if (labels.length < 2 || labels.some((label) => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
    fail("DOMAIN_INVALID", "Domain labels are invalid");
  }
  return hostname;
}

function validateFormat(value, format, context) {
  switch (format) {
    case "id":
      if (!ID_RE.test(value)) fail("ID_INVALID", "Identifier is malformed");
      return value;
    case "idempotency-key":
      if (!IDEMPOTENCY_RE.test(value)) fail("IDEMPOTENCY_KEY_INVALID", "Idempotency key is malformed");
      return value;
    case "artifact-ref":
      if (!ARTIFACT_RE.test(value)) fail("ARTIFACT_REF_INVALID", "Artifact reference is malformed");
      return value;
    case "project-path":
      return validateProjectPath(value, context.authorizedSubpaths || [""]);
    case "domain":
      return normalizeDomain(value);
    default:
      return value;
  }
}

function validateSchema(value, schema, pathLabel = "$", context = {}) {
  if (!schema || typeof schema !== "object") fail("SCHEMA_INVALID", `Missing schema at ${pathLabel}`);
  switch (schema.type) {
    case "object": {
      if (!value || typeof value !== "object" || Array.isArray(value)) fail("TYPE_INVALID", `${pathLabel} must be an object`);
      const properties = schema.properties || {};
      const required = new Set(schema.required || []);
      for (const key of required) if (!(key in value)) fail("FIELD_REQUIRED", `${pathLabel}.${key} is required`);
      if (schema.additionalProperties === false) {
        for (const key of Object.keys(value)) if (!(key in properties)) fail("UNKNOWN_FIELD", `${pathLabel}.${key} is not allowed`);
      }
      const normalized = {};
      for (const [key, childSchema] of Object.entries(properties)) {
        if (value[key] !== undefined) normalized[key] = validateSchema(value[key], childSchema, `${pathLabel}.${key}`, context);
      }
      return normalized;
    }
    case "array": {
      if (!Array.isArray(value)) fail("TYPE_INVALID", `${pathLabel} must be an array`);
      if (schema.minItems !== undefined && value.length < schema.minItems) fail("ARRAY_TOO_SHORT", `${pathLabel} has too few items`);
      if (schema.maxItems !== undefined && value.length > schema.maxItems) fail("ARRAY_TOO_LONG", `${pathLabel} has too many items`);
      return value.map((item, index) => validateSchema(item, schema.items, `${pathLabel}[${index}]`, context));
    }
    case "string": {
      if (typeof value !== "string") fail("TYPE_INVALID", `${pathLabel} must be a string`);
      if (schema.minLength !== undefined && value.length < schema.minLength) fail("STRING_TOO_SHORT", `${pathLabel} is too short`);
      if (schema.maxLength !== undefined && value.length > schema.maxLength) fail("STRING_TOO_LONG", `${pathLabel} is too long`);
      if (schema.enum && !schema.enum.includes(value)) fail("ENUM_INVALID", `${pathLabel} is not an allowed value`);
      if (schema.pattern && !(new RegExp(schema.pattern).test(value))) fail("PATTERN_INVALID", `${pathLabel} does not match the required pattern`);
      return schema.format ? validateFormat(value, schema.format, context) : value;
    }
    case "integer": {
      if (!Number.isInteger(value)) fail("TYPE_INVALID", `${pathLabel} must be an integer`);
      if (schema.minimum !== undefined && value < schema.minimum) fail("NUMBER_TOO_SMALL", `${pathLabel} is below minimum`);
      if (schema.maximum !== undefined && value > schema.maximum) fail("NUMBER_TOO_LARGE", `${pathLabel} exceeds maximum`);
      return value;
    }
    case "boolean":
      if (typeof value !== "boolean") fail("TYPE_INVALID", `${pathLabel} must be a boolean`);
      return value;
    default:
      fail("SCHEMA_TYPE_UNSUPPORTED", `Unsupported schema type at ${pathLabel}`);
  }
}

function validateToolProposal(proposal, context = {}) {
  const envelopeSchema = {
    type: "object",
    additionalProperties: false,
    required: ["tool", "version", "arguments"],
    properties: {
      tool: { type: "string", minLength: 1, maxLength: 100 },
      version: { type: "integer", minimum: 1, maximum: 100 },
      arguments: { type: "object", properties: {}, required: [], additionalProperties: true },
      reason: { type: "string", minLength: 1, maxLength: 1000 },
      requirement_refs: { type: "array", items: { type: "string", minLength: 1, maxLength: 128 }, maxItems: 50 },
    },
  };
  if (!proposal || typeof proposal !== "object" || Array.isArray(proposal)) fail("PROPOSAL_INVALID", "Tool proposal must be an object");
  for (const key of Object.keys(proposal)) if (!(key in envelopeSchema.properties)) fail("UNKNOWN_FIELD", `$.${key} is not allowed`);
  for (const key of envelopeSchema.required) if (!(key in proposal)) fail("FIELD_REQUIRED", `$.${key} is required`);
  const toolName = validateSchema(proposal.tool, envelopeSchema.properties.tool, "$.tool", context);
  const version = validateSchema(proposal.version, envelopeSchema.properties.version, "$.version", context);
  const definition = getToolDefinition(toolName, version);
  if (!definition) throw new PandoraToolError("authorization", "UNKNOWN_TOOL", `Unknown or unsupported tool version: ${toolName}@${version}`);
  const rawBytes = Buffer.byteLength(JSON.stringify(proposal.arguments ?? null), "utf8");
  if (rawBytes > definition.maxPayloadBytes) fail("PAYLOAD_TOO_LARGE", `Tool payload exceeds ${definition.maxPayloadBytes} bytes`);
  const args = validateSchema(proposal.arguments, definition.inputSchema, "$.arguments", context);
  const normalized = { tool: toolName, version, arguments: args };
  if (proposal.reason !== undefined) normalized.reason = validateSchema(proposal.reason, envelopeSchema.properties.reason, "$.reason", context);
  if (proposal.requirement_refs !== undefined) normalized.requirement_refs = validateSchema(proposal.requirement_refs, envelopeSchema.properties.requirement_refs, "$.requirement_refs", context);
  return { definition, proposal: normalized, payloadBytes: rawBytes };
}

module.exports = { validateSchema, validateToolProposal, normalizeDomain, ID_RE, ARTIFACT_RE };
