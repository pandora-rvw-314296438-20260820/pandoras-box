
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const runtime = require("../packages/pandora-project-runtime/src/index.js");

const ids = {
  organizationId: "11111111-1111-4111-8111-111111111111",
  projectId: "22222222-2222-4222-8222-222222222222",
  projectVersionId: "33333333-3333-4333-8333-333333333333",
  expectedProductionVersionId: "44444444-4444-4444-8444-444444444444",
};
const artifactDigest = "a".repeat(64);
const sourceCommit = "b".repeat(40);
function request(overrides = {}) {
  return { ...ids, environment: "preview", artifactDigest, sourceCommit, authorizationRef: "authz:worker-c:123", verificationRef: "verify:worker-e:456", provider: "vercel", runtimeType: "web_app", ...overrides };
}

test("exact version request rejects ambiguous lineage or missing authority", () => {
  assert.throws(() => runtime.normalizeDeploymentRequest({ ...request(), projectVersionId: "" }), /projectVersionId is required/);
  assert.throws(() => runtime.normalizeDeploymentRequest({ ...request(), artifactDigest: "latest" }), /SHA-256/);
  assert.throws(() => runtime.normalizeDeploymentRequest({ ...request(), authorizationRef: "" }), /authorizationRef is required/);
  assert.throws(() => runtime.normalizeDeploymentRequest({ ...request(), verificationRef: "" }), /verificationRef is required/);
});

test("production requires compare-and-set precondition", () => {
  assert.throws(() => runtime.normalizeDeploymentRequest({ ...request(), environment: "production", expectedProductionVersionId: null }), /production publish requires/);
  const exact = runtime.normalizeDeploymentRequest({ ...request(), environment: "production", expectedProductionVersionId: ids.expectedProductionVersionId });
  assert.equal(runtime.assertProductionPrecondition(ids.expectedProductionVersionId, exact), true);
  assert.throws(() => runtime.assertProductionPrecondition(ids.projectVersionId, exact), error => error.code === "PRODUCTION_PRECONDITION_FAILED");
});

test("first production publish requires an explicit empty-state precondition", () => {
  const first = runtime.normalizeDeploymentRequest({ ...request(), environment: "production", expectedProductionVersionId: null, allowFirstProduction: true });
  assert.equal(runtime.assertProductionPrecondition(null, first), true);
});

test("idempotency identity is stable and changes with exact version", () => {
  const first = runtime.operationIdempotencyKey("publish_version", request());
  const same = runtime.operationIdempotencyKey("publish_version", { ...request() });
  const changed = runtime.operationIdempotencyKey("publish_version", request({ projectVersionId: "55555555-5555-4555-8555-555555555555" }));
  assert.equal(first, same);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.notEqual(first, changed);
});

test("provider lineage fact must equal exact requested artifact/version/commit", () => {
  const input = request();
  assert.equal(runtime.assertExactLineage(input, { projectVersionId: input.projectVersionId, artifactDigest, sourceCommit }), true);
  assert.throws(() => runtime.assertExactLineage(input, { projectVersionId: input.projectVersionId, artifactDigest: "c".repeat(64), sourceCommit }), /artifact lineage mismatch/);
});

test("domain normalization rejects URL material and supports IDN", () => {
  assert.equal(runtime.normalizeDomain("Example.COM."), "example.com");
  assert.equal(runtime.normalizeDomain("bücher.example"), "xn--bcher-kva.example");
  assert.throws(() => runtime.normalizeDomain("https://example.com"), /scheme/);
  assert.throws(() => runtime.normalizeDomain("example.com/path"), /path/);
  assert.throws(() => runtime.normalizeDomain("example.com:443"), /port/);
  assert.throws(() => runtime.normalizeDomain(" example.com"), /whitespace/);
});

test("domain truth separates ownership DNS TLS routing and runtime health", () => {
  assert.equal(runtime.domainStateFromFacts({}), "verification_required");
  assert.equal(runtime.domainStateFromFacts({ ownershipVerified: true }), "dns_required");
  assert.equal(runtime.domainStateFromFacts({ ownershipVerified: true, dnsConfigured: true }), "tls_pending");
  assert.equal(runtime.domainStateFromFacts({ ownershipVerified: true, dnsConfigured: true, tlsReady: true }), "routing_pending");
  assert.equal(runtime.domainStateFromFacts({ ownershipVerified: true, dnsConfigured: true, tlsReady: true, routingReady: true, runtimeHealthy: true }), "ready");
});

test("provider READY is only ready for independent verification", () => {
  assert.equal(runtime.deploymentStateFromProvider("READY"), "ready_for_verification");
  assert.notEqual(runtime.deploymentStateFromProvider("READY"), "live_verified");
  assert.equal(runtime.deploymentStateFromProvider("BUILDING"), "building");
  assert.equal(runtime.deploymentStateFromProvider("ERROR"), "failed");
});

test("timeout after possible mutation is ambiguous and must reconcile", () => {
  const normalized = runtime.normalizeProviderError({ message: "request timed out", mutationMayHaveCommitted: true });
  assert.equal(normalized.kind, "ambiguous_mutation");
  assert.equal(normalized.ambiguous, true);
});

test("rate-limit normalization preserves retry metadata", () => {
  const normalized = runtime.normalizeProviderError({ status: 429, code: "rate_limit", retryAfterMs: 30000 });
  assert.equal(normalized.kind, "rate_limit");
  assert.equal(normalized.retryAfterMs, 30000);
});

test("provider secret redaction removes key and inline credential material", () => {
  const redacted = runtime.redactProviderData({ authorization: "Bearer super-secret-token", nested: { service_role_key: "sb_secret_abcdefghijklmnop", message: "failed with Bearer abcdefghijklmnop", connection: "postgresql://admin:hunter2@example.invalid/db" } });
  assert.equal(redacted.authorization, "[REDACTED_SECRET]");
  assert.equal(redacted.nested.service_role_key, "[REDACTED_SECRET]");
  assert.doesNotMatch(redacted.nested.message, /abcdefghijklmnop/);
  assert.doesNotMatch(redacted.nested.connection, /admin:hunter2/);
});

test("reconciliation is bounded for terminal states and provider retry windows", () => {
  const now = Date.parse("2026-08-28T15:00:30Z");
  assert.equal(runtime.shouldReconcileDeployment({ status: "ready_for_verification" }, now), false);
  assert.equal(runtime.shouldReconcileDeployment({ status: "building", lastProviderCheckAt: "2026-08-28T15:00:25Z", retryAfterMs: 10000 }, now), false);
  assert.equal(runtime.shouldReconcileDeployment({ status: "building", lastProviderCheckAt: "2026-08-28T15:00:00Z", retryAfterMs: 10000 }, now), true);
});

test("Simple Mode projection contains no provider identifiers", () => {
  assert.equal(runtime.ownerSafeStatus({ productionState: "live_verified", domainState: "ready" }), "Live");
  assert.equal(runtime.ownerSafeStatus({ productionState: "deploying", providerDeploymentId: "dpl_internal" }), "Publishing");
  assert.equal(runtime.ownerSafeStatus({ previewState: "ready_for_verification", previewVerified: true }), "Preview ready");
});


test("artifact snapshot runtime lineage is exact without a synthetic git commit", () => {
  const input = request({ sourceCommit: null, sourceKind: "artifact_snapshot", sourceRef: ids.projectVersionId });
  const exact = runtime.normalizeDeploymentRequest(input);
  assert.equal(exact.sourceKind, "artifact_snapshot");
  assert.equal(exact.sourceRef, ids.projectVersionId);
  assert.equal(exact.sourceCommit, null);
  assert.equal(runtime.assertExactLineage(input, { projectVersionId: ids.projectVersionId, artifactDigest, sourceKind: "artifact_snapshot", sourceRef: ids.projectVersionId, sourceCommit: null }), true);
  assert.throws(() => runtime.assertExactLineage(input, { projectVersionId: ids.projectVersionId, artifactDigest, sourceKind: "git_commit", sourceRef: sourceCommit, sourceCommit }), /source identity mismatch/);
});
