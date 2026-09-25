"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { auditIdentity } = require("../scripts/audit-fb004-identity.cjs");
const observed = require("../docs/growth/evidence/fb004-20260925.json");
const clock = { now: Date.parse("2026-09-25T09:00:00Z") };
function valid() {
  const s = structuredClone(observed);
  s.primary.campaigns.find((c) => c.slug === s.expected.campaignSlug).provider_campaign_bound = true;
  s.primary.metaConnections = [{ organization_id: s.expected.organizationId, credential_reference_present: true }];
  s.memory.grants[0].allowed_record_types.push("outcome");
  return s;
}
function tenant(s) { return s.primary.tenants.find((r) => r.id === s.expected.trackingTenantId); }
function memoryProject(s) { return s.memory.projects.find((r) => r.id === s.expected.memoryProjectId); }
function codes(s, options = clock) { return auditIdentity(s, options).findings.map((f) => f.code); }
function rejects(name, mutate, expected) {
  test(name, () => { const s = valid(); mutate(s); assert.ok(codes(s).includes(expected)); });
}
test("observed gaps are reproduced, not converted into authorization", () => {
  assert.deepEqual(codes(observed), ["META_CAMPAIGN_UNBOUND", "IDENTITY_MISSING", "MEMORY_PROPOSAL_CLASS_DENIED"]);
  const r = auditIdentity(observed, clock);
  assert.equal(r.authorizationEffect, "none"); assert.equal(r.productionVerified, false);
});
test("synthetically complete identity graph remains only a snapshot", () => {
  const r = auditIdentity(valid(), clock);
  assert.equal(r.status, "consistent_snapshot"); assert.equal(r.snapshotOnly, true);
  assert.equal(r.authorizationEffect, "none"); assert.equal(r.productionVerified, false);
});
test("unbound smoke tenant and another project sharing the repository do not select authority", () => {
  assert.equal(codes(valid()).length, 0);
});
rejects("wrong organization on primary project", (s) => { s.primary.projects[0].organization_id = "other"; }, "PRIMARY_PROJECT_SCOPE_MISMATCH");
rejects("registry must agree independently", (s) => { s.primary.registries[0].organization_id = "other"; }, "CANONICAL_REGISTRY_SCOPE_MISMATCH");
rejects("wrong tracking organization", (s) => { tenant(s).organization_id = "other"; }, "TRACKING_TENANT_SCOPE_MISMATCH");
rejects("unbound selected tracking tenant", (s) => { tenant(s).project_id = null; }, "TRACKING_TENANT_SCOPE_MISMATCH");
rejects("wrong tenant campaign", (s) => { s.primary.campaigns[0].tenant_id = "other"; }, "CAMPAIGN_TENANT_MISMATCH");
rejects("another organization's connection is not a fallback", (s) => { s.primary.metaConnections[0].organization_id = "other"; }, "IDENTITY_MISSING");
rejects("missing credential reference stays unknown", (s) => { delete s.primary.metaConnections[0].credential_reference_present; }, "META_CREDENTIAL_REFERENCE_MISSING");
rejects("primary project UUID is not a Memory UUID", (s) => { s.expected.memoryProjectId = s.expected.primaryProjectId; }, "IDENTITY_MISSING");
rejects("shared repository cannot resolve an ambiguous project", (s) => { s.memory.projects.push(structuredClone(memoryProject(s))); }, "AMBIGUOUS_IDENTITY");
rejects("wrong Memory key cannot be papered over by same repository", (s) => { memoryProject(s).project_key = "enterprise-eurofish"; }, "MEMORY_PROJECT_SCOPE_MISMATCH");
rejects("wrong namespace", (s) => { memoryProject(s).memory_namespace = "au"; }, "MEMORY_PROJECT_SCOPE_MISMATCH");
rejects("wrong environment", (s) => { s.memory.principals[0].environment = "preview"; }, "MEMORY_PRINCIPAL_SCOPE_MISMATCH");
rejects("inactive principal", (s) => { s.memory.principals[0].is_active = false; }, "MEMORY_PRINCIPAL_SCOPE_MISMATCH");
rejects("wrong principal grant", (s) => { s.memory.grants[0].principal_key = "other"; }, "IDENTITY_MISSING");
rejects("wrong project grant", (s) => { s.memory.grants[0].project_id = "other"; }, "IDENTITY_MISSING");
rejects("revoked grant", (s) => { s.memory.grants[0].revoked = true; }, "MEMORY_GRANT_INACTIVE");
rejects("null revoke state", (s) => { s.memory.grants[0].revoked = null; }, "MEMORY_GRANT_INACTIVE");
rejects("read class is exact", (s) => { s.memory.grants[0].allowed_record_types = ["outcome"]; }, "MEMORY_READ_CLASS_DENIED");
rejects("proposal class is exact", (s) => { s.memory.grants[0].allowed_record_types = ["integration_state"]; }, "MEMORY_PROPOSAL_CLASS_DENIED");
rejects("proposal is not approval", (s) => { s.memory.grants[0].can_approve = true; }, "MEMORY_APPROVAL_SEPARATION_UNPROVEN");
rejects("truthy strings are not permissions", (s) => { s.memory.grants[0].can_propose = "true"; }, "MEMORY_PROPOSAL_CLASS_DENIED");
rejects("retired principal is not a fallback", (s) => { s.expected.principalKey = "projectos-mcpmaster-production"; }, "INVALID_TRUSTED_MANIFEST");
rejects("missing rows cannot silently mean empty verified evidence", (s) => { delete s.memory.grants; }, "MISSING_OR_INVALID_ROWS");
rejects("duplicate grants cannot choose first row", (s) => { s.memory.grants.push(structuredClone(s.memory.grants[0])); }, "AMBIGUOUS_IDENTITY");
rejects("old observations fail closed", (s) => { s.memory.observedAt = "2026-09-24T00:00:00Z"; }, "STALE_OR_INVALID_OBSERVATION");
rejects("future observations fail closed", (s) => { s.primary.observedAt = "2026-09-26T00:00:00Z"; }, "STALE_OR_INVALID_OBSERVATION");
rejects("timezone-free observations are rejected", (s) => { s.primary.observedAt = "2026-09-25T08:50:00"; }, "STALE_OR_INVALID_OBSERVATION");
rejects("sensitive input fields are refused", (s) => { s.primary.access_token = "synthetic-do-not-echo"; }, "SENSITIVE_INPUT_REJECTED");
test("malformed input and invalid audit options fail closed", () => {
  for (const value of [null, [], {}, "invalid", { schemaVersion: 2 }]) assert.equal(auditIdentity(value, clock).status, "blocked");
  assert.ok(codes(valid(), { now: NaN }).includes("INVALID_AUDIT_CLOCK"));
  assert.ok(codes(valid(), { ...clock, maxAgeMs: 0 }).includes("INVALID_AUDIT_CLOCK"));
});
test("CLI rejects invalid JSON without echoing payload or path", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fb004-"));
  const file = path.join(dir, "sensitive-name.json");
  try {
    fs.writeFileSync(file, "synthetic-do-not-echo");
    const r = spawnSync(process.execPath, [path.resolve(__dirname, "../scripts/audit-fb004-identity.cjs"), file], { encoding: "utf8" });
    assert.equal(r.status, 2); assert.doesNotMatch(r.stderr + r.stdout, /synthetic-do-not-echo|sensitive-name/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

rejects("unsupported learning class is not inferred from a broad grant", (s) => { s.expected.proposalRecordType = "governance_rule"; }, "INVALID_TRUSTED_MANIFEST");
rejects("non-array record types fail closed", (s) => { s.memory.grants[0].allowed_record_types = "outcome"; }, "MEMORY_PROPOSAL_CLASS_DENIED");
rejects("oversized arrays are rejected", (s) => { s.memory.grants = Array(1001).fill({}); }, "MISSING_OR_INVALID_ROWS");
test("excessively nested input is refused", () => {
  const s = valid(); let n = s;
  for (let i=0; i<14; i++) { n.extra = {}; n = n.extra; }
  assert.ok(codes(s).includes("INPUT_TOO_COMPLEX"));
});
test("CLI returns 0 for a consistent synthetic snapshot and 1 for observed blockers", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fb004-"));
  const file = path.join(dir, "snapshot.json");
  try {
    for (const [s, expected] of [[valid(), 0], [structuredClone(observed), 1]]) {
      s.primary.observedAt = s.memory.observedAt = new Date().toISOString();
      fs.writeFileSync(file, JSON.stringify(s));
      const r = spawnSync(process.execPath, [path.resolve(__dirname, "../scripts/audit-fb004-identity.cjs"), file], { encoding: "utf8" });
      assert.equal(r.status, expected, r.stderr); const report = JSON.parse(r.stdout);
      assert.match(report.inputSha256, /^[a-f0-9]{64}$/); assert.equal(report.authorizationEffect, "none");
    }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test("CLI refuses oversized input and missing files without data leakage", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fb004-"));
  const file = path.join(dir, "synthetic-large.json");
  try {
    fs.writeFileSync(file, " ".repeat(1048577));
    for (const target of [file, path.join(dir, "private-path")]) {
      const r = spawnSync(process.execPath, [path.resolve(__dirname, "../scripts/audit-fb004-identity.cjs"), target], { encoding: "utf8" });
      assert.equal(r.status, 2); assert.doesNotMatch(r.stderr + r.stdout, /synthetic-large|private-path/);
    }
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
test("both replayable inventory probes are single read-only statements", () => {
  for (const name of ["primary", "memory"]) {
    const sql = fs.readFileSync(path.resolve(__dirname, `../scripts/sql/fb004-${name}-readback.sql`), "utf8").replace(/--[^\n]*/g, "").trim();
    assert.match(sql, /^select\b/i); assert.equal((sql.match(/;/g) || []).length, 1);
    assert.doesNotMatch(sql, /\b(insert|update|delete|create|alter|drop|truncate|grant|revoke)\b/i);
    assert.doesNotMatch(sql, /vault\.decrypted_secrets|secret_value|raw_excerpt|user_token\s*[,)]/i);
  }
});
