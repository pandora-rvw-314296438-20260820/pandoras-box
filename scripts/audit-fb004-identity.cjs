"use strict";

// Offline inventory validation only. Never import this as a runtime authorizer.
const fs = require("node:fs");
const crypto = require("node:crypto");
const CANONICAL_REPOSITORY = "pandora-rvw-314296438-20260820/pandoras-box";
const SENSITIVE_KEYS = /^(access_token|user_token|app_secret|client_secret|secret_value|service_role_key|api_key|authorization|cookie|password|raw_excerpt|content)$/i;
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v) => typeof v === "string" && v.length > 0 && v.length <= 256 && v.trim() === v;
const strings = (v) => Array.isArray(v) && v.length <= 1000 && v.every(text);
const timestamp = (v) => typeof v === "string" && /(?:Z|[+-]\d{2}:\d{2})$/.test(v) && Number.isFinite(Date.parse(v));

function auditIdentity(input, options = {}) {
  const findings = [];
  const add = (code, area) => findings.push({ code, area });
  const result = () => ({
    schemaVersion: 1,
    task: "FB-004",
    snapshotOnly: true,
    authorizationEffect: "none",
    productionVerified: false,
    status: findings.length ? "blocked" : "consistent_snapshot",
    findings,
  });
  const now = options.now === undefined ? Date.now() : options.now;
  const maxAgeMs = options.maxAgeMs === undefined ? 3600000 : options.maxAgeMs;
  if (!Number.isFinite(now) || !Number.isFinite(maxAgeMs) || maxAgeMs <= 0) {
    add("INVALID_AUDIT_CLOCK", "evidence"); return result();
  }
  // Reject secret-bearing input without including any input values in the output.
  const stack = [{ value: input, depth: 0 }];
  let nodes = 0;
  while (stack.length) {
    const { value, depth } = stack.pop();
    if (++nodes > 20000 || depth > 12) {
      add("INPUT_TOO_COMPLEX", "evidence"); return result();
    }
    if (value && typeof value === "object") {
      for (const [key, child] of Object.entries(value)) {
        if (SENSITIVE_KEYS.test(key)) {
          add("SENSITIVE_INPUT_REJECTED", "evidence"); return result();
        }
        stack.push({ value: child, depth: depth + 1 });
      }
    }
  }
  if (!object(input) || input.schemaVersion !== 1 || !object(input.expected)
      || !object(input.primary) || !object(input.memory)) {
    add("INVALID_SNAPSHOT", "evidence"); return result();
  }
  const e = input.expected;
  const required = ["organizationId", "primaryProjectId", "trackingTenantId", "campaignSlug",
    "memoryProjectId", "memoryProjectKey", "principalKey", "environment", "namespace",
    "repository", "readRecordType", "proposalRecordType"];
  if (!required.every((k) => text(e[k])) || e.repository !== CANONICAL_REPOSITORY
      || e.environment !== "production" || e.namespace !== "real_life"
      || e.principalKey.toLowerCase().includes("projectos")
      || !["fact", "procedure", "failure_lesson", "outcome"].includes(e.proposalRecordType)) {
    add("INVALID_TRUSTED_MANIFEST", "evidence"); return result();
  }
  for (const plane of ["primary", "memory"]) {
    const t = input[plane].observedAt;
    if (!timestamp(t) || Date.parse(t) > now + 60000 || now - Date.parse(t) > maxAgeMs) {
      add("STALE_OR_INVALID_OBSERVATION", plane);
    }
  }
  function rows(plane, key) {
    const value = input[plane][key];
    if (!Array.isArray(value) || value.length > 1000 || !value.every(object)) {
      add("MISSING_OR_INVALID_ROWS", `${plane}.${key}`); return [];
    }
    return value;
  }
  function one(values, predicate, area) {
    const matches = values.filter(predicate);
    if (matches.length !== 1) { add(matches.length ? "AMBIGUOUS_IDENTITY" : "IDENTITY_MISSING", area); return null; }
    return matches[0];
  }
  const projects = rows("primary", "projects");
  const registries = rows("primary", "registries");
  const tenants = rows("primary", "tenants");
  const campaigns = rows("primary", "campaigns");
  const connections = rows("primary", "metaConnections");
  const memoryProjects = rows("memory", "projects");
  const principals = rows("memory", "principals");
  const grants = rows("memory", "grants");
  const p = one(projects, (r) => r.id === e.primaryProjectId, "primary.project");
  if (p && (p.organization_id !== e.organizationId || p.repository !== e.repository || p.status !== "active")) {
    add("PRIMARY_PROJECT_SCOPE_MISMATCH", "primary.project");
  }
  const r = one(registries, (v) => v.project_id === e.primaryProjectId, "primary.registry");
  if (r && (r.organization_id !== e.organizationId || r.canonical_repository !== e.repository)) {
    add("CANONICAL_REGISTRY_SCOPE_MISMATCH", "primary.registry");
  }
  const t = one(tenants, (v) => v.id === e.trackingTenantId, "tracking.tenant");
  if (t && (t.organization_id !== e.organizationId || t.project_id !== e.primaryProjectId || t.status !== "active")) {
    add("TRACKING_TENANT_SCOPE_MISMATCH", "tracking.tenant");
  }
  const c = one(campaigns, (v) => v.slug === e.campaignSlug, "tracking.campaign");
  if (c && (c.tenant_id !== e.trackingTenantId || c.provider !== "meta")) {
    add("CAMPAIGN_TENANT_MISMATCH", "tracking.campaign");
  }
  if (c && c.provider_campaign_bound !== true) add("META_CAMPAIGN_UNBOUND", "tracking.campaign");
  const connection = one(connections, (v) => v.organization_id === e.organizationId, "meta.connection");
  if (connection && connection.credential_reference_present !== true) {
    add("META_CREDENTIAL_REFERENCE_MISSING", "meta.connection");
  }
  // This tests reference presence, NOT token validity, permissions or asset authorization.
  const m = one(memoryProjects, (v) => v.id === e.memoryProjectId, "memory.project");
  if (m && (m.project_key !== e.memoryProjectKey || m.memory_namespace !== e.namespace
      || `${m.github_owner}/${m.github_repository}` !== e.repository || m.lifecycle_status !== "active")) {
    add("MEMORY_PROJECT_SCOPE_MISMATCH", "memory.project");
  }
  const principal = one(principals, (v) => v.principal_key === e.principalKey, "memory.principal");
  if (principal && (principal.is_active !== true || principal.environment !== e.environment
      || !strings(principal.allowed_namespaces) || !principal.allowed_namespaces.includes(e.namespace)
      || !strings(principal.scopes) || !principal.scopes.includes("memory:read") || !principal.scopes.includes("memory:write"))) {
    add("MEMORY_PRINCIPAL_SCOPE_MISMATCH", "memory.principal");
  }
  const grant = one(grants, (v) => v.project_id === e.memoryProjectId
    && v.principal_key === e.principalKey && v.environment === e.environment, "memory.grant");
  if (grant) {
    if (grant.is_active !== true || grant.revoked !== false) add("MEMORY_GRANT_INACTIVE", "memory.grant");
    if (grant.can_read !== true || !strings(grant.allowed_record_types)
        || !grant.allowed_record_types.includes(e.readRecordType)) add("MEMORY_READ_CLASS_DENIED", "memory.grant");
    if (grant.can_propose !== true || !strings(grant.allowed_record_types)
        || !grant.allowed_record_types.includes(e.proposalRecordType)) add("MEMORY_PROPOSAL_CLASS_DENIED", "memory.grant");
    if (grant.can_approve !== false) add("MEMORY_APPROVAL_SEPARATION_UNPROVEN", "memory.grant");
  }
  return result();
}

function main(argv) {
  try {
    if (argv.length !== 1) throw new Error("usage");
    // A read-only FIFO can block during open, before fstat can reject it.
    // Keep descriptor-based validation; a path precheck alone would be racy.
    // O_NONBLOCK is optional on platforms such as Windows.
    const fd = fs.openSync(argv[0], fs.constants.O_RDONLY | (fs.constants.O_NONBLOCK || 0));
    let raw;
    try {
      const stat = fs.fstatSync(fd);
      if (!stat.isFile() || stat.size > 1048576) throw new Error("size");
      raw = fs.readFileSync(fd, "utf8");
      if (Buffer.byteLength(raw) > 1048576) throw new Error("size");
    } finally { fs.closeSync(fd); }
    const result = auditIdentity(JSON.parse(raw));
    result.inputSha256 = crypto.createHash("sha256").update(raw).digest("hex");
    console.log(JSON.stringify(result, null, 2));
    return result.status === "consistent_snapshot" ? 0 : 1;
  } catch {
    // Never print a supplied path, JSON excerpt, secret, or exception body.
    console.error("FB004_INPUT_ERROR: supply one bounded, secret-free JSON snapshot file");
    return 2;
  }
}
if (require.main === module) process.exitCode = main(process.argv.slice(2));
module.exports = { auditIdentity };
