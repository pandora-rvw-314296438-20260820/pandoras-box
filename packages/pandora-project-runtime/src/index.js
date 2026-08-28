
"use strict";

const { createHash } = require("node:crypto");
const { domainToASCII } = require("node:url");

const RUNTIME_ENVIRONMENTS = Object.freeze(["development", "preview", "production"]);
const RUNTIME_TYPES = Object.freeze(["static_site", "web_app", "mobile_support"]);
const DEPLOYMENT_STATES = Object.freeze(["requested", "queued", "building", "ready_for_verification", "failed", "cancelled"]);
const PRODUCTION_STATES = Object.freeze(["requested", "deploying", "ready_for_verification", "live_verified", "failed", "rolled_back", "drifted", "verification_expired"]);
const DOMAIN_STATES = Object.freeze(["verification_required", "dns_required", "tls_pending", "routing_pending", "ready", "failed"]);
const RUNTIME_ERROR_KINDS = Object.freeze(["authorization", "rate_limit", "quota", "timeout", "network", "conflict", "not_found", "invalid_configuration", "domain_verification", "deployment_failed", "build_failed", "provider_unavailable", "ambiguous_mutation"]);
const terminalDeploymentStates = new Set(["ready_for_verification", "failed", "cancelled"]);
const secretKey = /(?:authorization|cookie|password|passphrase|secret|token|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|private[_-]?key|connection[_-]?string|service[_-]?role)/i;

function nonEmpty(value, field) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${field} is required`);
  return value.trim();
}
function uuid(value, field) {
  const v = nonEmpty(value, field).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v)) throw new Error(`${field} must be a UUID`);
  return v;
}
function sha256(value, field = "artifactDigest") {
  const v = nonEmpty(value, field).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(v)) throw new Error(`${field} must be a lowercase SHA-256 digest`);
  return v;
}
function sourceCommit(value) {
  const v = nonEmpty(value, "sourceCommit").toLowerCase();
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(v)) throw new Error("sourceCommit must be an immutable commit SHA");
  return v;
}
function environment(value) {
  const v = nonEmpty(value, "environment").toLowerCase();
  if (!RUNTIME_ENVIRONMENTS.includes(v)) throw new Error(`unsupported runtime environment: ${v}`);
  return v;
}
function canonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") { if (!Number.isFinite(value)) throw new Error("non-finite number"); return JSON.stringify(value); }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).filter(k => value[k] !== undefined).sort().map(k => `${JSON.stringify(k)}:${canonicalJson(value[k])}`).join(",")}}`;
  throw new Error(`unsupported canonical JSON value: ${typeof value}`);
}

function normalizeDeploymentRequest(input) {
  const request = {
    organizationId: uuid(input.organizationId, "organizationId"),
    projectId: uuid(input.projectId, "projectId"),
    projectVersionId: uuid(input.projectVersionId, "projectVersionId"),
    artifactDigest: sha256(input.artifactDigest),
    sourceCommit: sourceCommit(input.sourceCommit),
    environment: environment(input.environment),
    authorizationRef: nonEmpty(input.authorizationRef, "authorizationRef"),
    verificationRef: nonEmpty(input.verificationRef, "verificationRef"),
    provider: nonEmpty(input.provider || "vercel", "provider").toLowerCase(),
    runtimeType: nonEmpty(input.runtimeType || "web_app", "runtimeType").toLowerCase(),
    expectedProductionVersionId: input.expectedProductionVersionId ? uuid(input.expectedProductionVersionId, "expectedProductionVersionId") : null,
  };
  if (!RUNTIME_TYPES.includes(request.runtimeType)) throw new Error(`unsupported runtime type: ${request.runtimeType}`);
  if (request.environment === "production" && !request.expectedProductionVersionId && input.allowFirstProduction !== true) throw new Error("production publish requires an expected current version or explicit first-publish precondition");
  return Object.freeze(request);
}

function operationIdempotencyKey(action, input) {
  const request = normalizeDeploymentRequest({ ...input, allowFirstProduction: input.allowFirstProduction === true });
  return createHash("sha256").update(canonicalJson({ action: nonEmpty(action, "action"), ...request, target: input.target || null }), "utf8").digest("hex");
}

function assertExactLineage(input, fact) {
  const request = normalizeDeploymentRequest({ ...input, allowFirstProduction: input.allowFirstProduction === true });
  if (fact.projectVersionId !== request.projectVersionId) throw new Error("provider project version lineage mismatch");
  if (String(fact.artifactDigest || "").toLowerCase() !== request.artifactDigest) throw new Error("provider artifact lineage mismatch");
  if (String(fact.sourceCommit || "").toLowerCase() !== request.sourceCommit) throw new Error("provider source commit lineage mismatch");
  return true;
}

function assertProductionPrecondition(currentVersionId, request) {
  if (request.environment !== "production") return true;
  if ((currentVersionId || null) !== (request.expectedProductionVersionId || null)) {
    const error = new Error("production version precondition failed");
    error.code = "PRODUCTION_PRECONDITION_FAILED";
    throw error;
  }
  return true;
}

function normalizeDomain(input) {
  const raw = nonEmpty(input, "domain");
  if (raw !== raw.trim() || /\s/.test(raw)) throw new Error("domain must not contain whitespace");
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)) throw new Error("domain must not include a scheme");
  if (/[/?#]/.test(raw)) throw new Error("domain must not include a path, query, or fragment");
  if (raw.includes(":")) throw new Error("domain must not include a port");
  const ascii = domainToASCII(raw.replace(/\.$/, "").toLowerCase());
  if (!ascii || ascii.length > 253 || !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(ascii)) throw new Error("domain is invalid");
  return ascii;
}

function domainStateFromFacts(facts) {
  if (facts.failed === true) return "failed";
  if (facts.ownershipVerified !== true) return "verification_required";
  if (facts.dnsConfigured !== true) return "dns_required";
  if (facts.tlsReady !== true) return "tls_pending";
  if (facts.routingReady !== true || facts.runtimeHealthy !== true) return "routing_pending";
  return "ready";
}

function deploymentStateFromProvider(state) {
  const v = String(state || "").trim().toUpperCase();
  if (["READY", "SUCCEEDED", "SUCCESS"].includes(v)) return "ready_for_verification";
  if (["ERROR", "FAILED"].includes(v)) return "failed";
  if (["CANCELED", "CANCELLED"].includes(v)) return "cancelled";
  if (["BUILDING", "INITIALIZING"].includes(v)) return "building";
  if (["QUEUED", "PENDING"].includes(v)) return "queued";
  return "requested";
}

function shouldReconcileDeployment(record, now = Date.now()) {
  if (!record || terminalDeploymentStates.has(record.status)) return false;
  const last = record.lastProviderCheckAt ? Date.parse(record.lastProviderCheckAt) : 0;
  const delay = Number.isFinite(record.retryAfterMs) ? Math.max(0, record.retryAfterMs) : 15000;
  return !last || now - last >= delay;
}

function normalizeProviderError(error) {
  const status = Number(error?.status || error?.statusCode || 0);
  const code = String(error?.code || error?.providerCode || "").toLowerCase();
  const message = String(error?.message || "").toLowerCase();
  const text = `${code} ${message}`;
  let kind = "provider_unavailable", retryable = true, ambiguous = false;
  if (status === 401 || status === 403 || /auth|unauthor|forbidden/.test(text)) { kind = "authorization"; retryable = false; }
  else if (status === 429 || /rate.?limit/.test(text)) kind = "rate_limit";
  else if (/quota/.test(text)) { kind = "quota"; retryable = false; }
  else if (status === 404) { kind = "not_found"; retryable = false; }
  else if (status === 409 || /conflict/.test(text)) { kind = "conflict"; retryable = false; }
  else if (/domain/.test(text) && /verify|dns|tls|configuration/.test(text)) { kind = "domain_verification"; retryable = false; }
  else if (/build/.test(text) && /fail|error/.test(text)) { kind = "build_failed"; retryable = false; }
  else if (/deploy/.test(text) && /fail|error/.test(text)) { kind = "deployment_failed"; retryable = false; }
  else if (/timeout|timed out|abort|network|fetch|econn|socket/.test(text)) { ambiguous = Boolean(error?.mutationMayHaveCommitted); kind = ambiguous ? "ambiguous_mutation" : (/timeout|timed out|abort/.test(text) ? "timeout" : "network"); }
  else if (status >= 400 && status < 500) { kind = "invalid_configuration"; retryable = false; }
  return Object.freeze({ kind, retryable, ambiguous, status: status || null, retryAfterMs: Number.isFinite(error?.retryAfterMs) ? Math.max(0, error.retryAfterMs) : null, providerCode: code || null });
}

function redactProviderData(value, keyHint = "") {
  if (secretKey.test(keyHint)) return "[REDACTED_SECRET]";
  if (value === null || value === undefined) return value ?? null;
  if (typeof value === "string") return value
    .replace(/\bBearer\s+[A-Za-z0-9._~+/=-]+\b/gi, "[REDACTED_SECRET]")
    .replace(/\b(?:sk|sbp|sb_secret|vercel)_[A-Za-z0-9_-]{12,}\b/gi, "[REDACTED_SECRET]")
    .replace(/\bpostgres(?:ql)?:\/\/[^@\s]+@/gi, "[REDACTED_SECRET]@");
  if (Array.isArray(value)) return value.map(item => redactProviderData(item));
  if (typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, redactProviderData(child, key)]));
  return value;
}

function ownerSafeStatus(facts) {
  if (facts.productionState === "live_verified" && facts.domainState === "ready") return "Live";
  if (facts.productionState === "rolled_back") return "Rolled back";
  if (facts.domainState && !["ready", "failed"].includes(facts.domainState)) return "Domain needs setup";
  if (["requested", "deploying"].includes(facts.productionState)) return "Publishing";
  if (facts.previewState === "ready_for_verification" && facts.previewVerified === true) return "Preview ready";
  if (facts.previewState === "failed" || facts.productionState === "failed" || facts.domainState === "failed") return "Something needs attention";
  return "Preparing preview";
}

class DeploymentProvider {
  constructor(name) { this.name = nonEmpty(name, "provider name").toLowerCase(); }
  async createProjectRuntime() { throw new Error("not implemented"); }
  async createPreview() { throw new Error("not implemented"); }
  async getDeployment() { throw new Error("not implemented"); }
  async publishVersion() { throw new Error("not implemented"); }
  async attachDomain() { throw new Error("not implemented"); }
  async inspectDomain() { throw new Error("not implemented"); }
  async rollback() { throw new Error("not implemented"); }
  async deletePreview() { throw new Error("not implemented"); }
  async reconcile() { throw new Error("not implemented"); }
}
class ApplicationDatabaseProvider {
  constructor(name) { this.name = nonEmpty(name, "provider name").toLowerCase(); }
  async provisionRuntime() { throw new Error("not implemented"); }
  async inspectRuntime() { throw new Error("not implemented"); }
  async createBackup() { throw new Error("not implemented"); }
  async executeMigration() { throw new Error("not implemented"); }
  async recover() { throw new Error("not implemented"); }
}

module.exports = { ApplicationDatabaseProvider, DEPLOYMENT_STATES, DOMAIN_STATES, DeploymentProvider, PRODUCTION_STATES, RUNTIME_ENVIRONMENTS, RUNTIME_ERROR_KINDS, RUNTIME_TYPES, assertExactLineage, assertProductionPrecondition, canonicalJson, deploymentStateFromProvider, domainStateFromFacts, normalizeDeploymentRequest, normalizeDomain, normalizeProviderError, operationIdempotencyKey, ownerSafeStatus, redactProviderData, shouldReconcileDeployment };
