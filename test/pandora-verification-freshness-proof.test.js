
"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");

const D = (ch) => ch.repeat(64);
const C = (ch) => ch.repeat(40);
const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

function request(overrides = {}) {
  return {
    verification_run_id: U(1), organization_id: U(2), project_id: U(3), project_spec_id: U(4), project_spec_version: 12,
    project_version_id: U(5), source_commit: C("a"), source_digest: D("b"), artifact_digest: D("c"), migration_set_digest: D("d"),
    preview_deployment_id: "preview-1", target_environment: "preview", runtime_target_digest: D("e"), required_check_profile: "static_site", requested_by: "worker-j",
    ...overrides,
  };
}

function passRequired(engine, authorityToken, runId) {
  const run = engine.getVerification(runId);
  for (const checkId of run.required_checks) engine.recordCheck(runId, authorityToken, { check_id: checkId, status: "PASS", evidence_refs: [`evidence:${checkId}`] });
}

test("fresh runtime and deployment evidence expires while exact-source evidence remains reusable", () => {
  let now = Date.parse("2026-08-29T00:00:00Z");
  const authorityToken = {};
  const engine = new verification.VerificationEngine({ authorityToken, clock: () => new Date(now) });
  const run = engine.requestVerification(request());
  engine.start(run.verification_run_id, authorityToken);
  passRequired(engine, authorityToken, run.verification_run_id);
  engine.finalize(run.verification_run_id, authorityToken);
  const initial = engine.getReleaseReadiness(run.verification_run_id);
  assert.equal(initial.publish_eligible, true);
  assert.equal(initial.freshness, "current");
  const source = engine.getVerification(run.verification_run_id).results.find((item) => item.check_id === "source_lint");
  const runtime = engine.getVerification(run.verification_run_id).results.find((item) => item.check_id === "runtime_health");
  assert.equal(source.expires_at, null);
  assert.match(runtime.expires_at, /^2026-08-29T00:30:00/);
  now += 31 * 60 * 1000;
  const expired = engine.getReleaseReadiness(run.verification_run_id);
  assert.equal(expired.publish_eligible, false);
  assert.equal(expired.freshness, "expired");
  assert.ok(expired.expired_checks.includes("runtime_health"));
});

test("freshness is a publish fact and does not rewrite historical PASS", () => {
  let now = Date.parse("2026-08-29T00:00:00Z");
  const authorityToken = {};
  const engine = new verification.VerificationEngine({ authorityToken, clock: () => new Date(now) });
  const run = engine.requestVerification(request());
  engine.start(run.verification_run_id, authorityToken); passRequired(engine, authorityToken, run.verification_run_id); engine.finalize(run.verification_run_id, authorityToken);
  now += 31 * 60 * 1000;
  assert.equal(engine.getVerification(run.verification_run_id).status, "PASS");
  assert.equal(engine.getVerificationFreshness(run.verification_run_id).state, "expired");
  assert.equal(engine.getReleaseReadiness(run.verification_run_id).publish_eligible, false);
});

test("Worker D verification requests carry exact source and no credentials", () => {
  const adapted = verification.buildWorkerDVerificationRequest({ verificationRequest: request(), checkId: "unit_tests", executionId: U(10), buildJobId: U(11), idempotencyKey: "verify-unit-v1", repository: "pandora-rvw-314296438-20260820/pandoras-box" });
  assert.equal(adapted.operation, "run_unit_tests");
  assert.equal(adapted.source.commitSha, C("a"));
  assert.deepEqual(adapted.credentialLeaseRefs, []);
  assert.deepEqual(adapted.networkPolicy, { mode: "deny", allow: [] });
  assert.equal("credentials" in adapted, false);
});

test("builder receipt alone cannot become authoritative Worker E PASS", () => {
  const receipt = { status: "completed", exitCode: 0, artifactRefs: ["artifact:test-report"] };
  assert.equal(verification.workerDResultToIndependentOutcome(receipt).status, "INCONCLUSIVE");
  const observed = verification.workerDResultToIndependentOutcome(receipt, { requestedByVerifier: true });
  assert.equal(observed.status, "PASS");
  assert.equal(observed.authoritative, true);
});

test("Worker F fact is translated to exact preview evidence", () => {
  const fact = verification.workerFDeploymentToEvidence({ providerDeploymentId: "dpl_test", url: "https://preview.invalid", providerState: "READY", projectVersionId: U(5), artifactDigest: D("c"), sourceCommit: C("a") });
  const verified = verification.verifyPreviewEvidence({ request: request(), deployment: fact, probes: [{ statusCode: 200 }] });
  assert.equal(verified.status, "PASS");
  const drifted = verification.verifyPreviewEvidence({ request: request(), deployment: { ...fact, artifact_digest: D("f") }, probes: [{ statusCode: 200 }] });
  assert.equal(drifted.status, "FAIL");
});

test("release report exposes machine decision, blockers and evidence", () => {
  const report = verification.createReleaseReadinessReport({ verification_run_id: U(1), project_spec_id: U(4), project_spec_version: 12, project_version_id: U(5), source_commit: C("a"), source_digest: D("b"), artifact_digest: D("c"), verification: "PASS", freshness: "expired", publish_eligible: false, required_checks: ["runtime_health"], failed_checks: [], blocked_checks: [], missing_checks: [], expired_checks: ["runtime_health"], requirement_coverage: [], evidence_refs: ["evidence:runtime"] });
  assert.equal(report.decision, "NOT_ELIGIBLE");
  assert.deepEqual(report.blockers, [{ type: "expired_check", check: "runtime_health" }]);
  assert.match(report.human_summary, /not publish eligible/i);
});

test("rollback verification re-verifies exact target and runtime", () => {
  const req = request({ target_environment: "production" });
  const deployment = { artifact_digest: D("c"), source_commit: C("a"), project_version_id: U(5), deployment_id: "rollback-1", url: "https://app.example" };
  const domain = { intended_domain: "app.example", observed_domain: "app.example", ownership_verified: true, dns_resolves: true, tls_valid: true, routing_correct: true, project_binding_correct: true };
  assert.equal(verification.verifyRollbackTarget({ request: req, targetVersionId: U(5), deployment, domain, probes: [{ statusCode: 200 }] }).status, "PASS");
  assert.equal(verification.verifyRollbackTarget({ request: req, targetVersionId: U(6), deployment, domain, probes: [{ statusCode: 200 }] }).status, "FAIL");
});

test("production drift distinguishes current, drifted, expired and unknown", () => {
  const base = { verifiedDeploymentId: "d1", currentDeploymentId: "d1", verifiedArtifactDigest: D("a"), currentArtifactDigest: D("a"), domainMatches: true, runtimeHealthy: true, now: Date.parse("2026-08-29T00:00:00Z") };
  assert.equal(verification.classifyProductionVerification(base), "verified_current");
  assert.equal(verification.classifyProductionVerification({ ...base, currentDeploymentId: "d2" }), "drift_detected");
  assert.equal(verification.classifyProductionVerification({ ...base, evidenceExpiresAt: "2026-08-28T23:59:00Z" }), "verification_expired");
  assert.equal(verification.classifyProductionVerification({ ...base, currentArtifactDigest: null }), "unknown");
});

test("repair history preserves failed run and records a new passing run", () => {
  const authorityToken = {};
  const engine = new verification.VerificationEngine({ authorityToken, clock: () => new Date("2026-08-29T00:00:00Z") });
  const first = engine.requestVerification(request()); engine.start(first.verification_run_id, authorityToken);
  for (const checkId of first.required_checks) engine.recordCheck(first.verification_run_id, authorityToken, { check_id: checkId, status: checkId === "runtime_health" ? "FAIL" : "PASS" });
  engine.finalize(first.verification_run_id, authorityToken);
  const second = engine.retry(first.verification_run_id, { verification_run_id: U(7), project_version_id: U(8), source_commit: C("8"), source_digest: D("8"), artifact_digest: D("8"), preview_deployment_id: "preview-2" });
  engine.start(second.verification_run_id, authorityToken); passRequired(engine, authorityToken, second.verification_run_id); engine.finalize(second.verification_run_id, authorityToken);
  const history = verification.historicalVerificationTimeline([engine.getVerification(first.verification_run_id), engine.getVerification(second.verification_run_id)]);
  assert.deepEqual(history.map((item) => item.status), ["FAIL", "PASS"]);
  assert.equal(history[1].retry_of, first.verification_run_id);
});

test("deterministic negative fixtures cover critical failure classes", () => {
  const canary = "PANDORA_CANARY_SECRET_FAKE123456789";
  assert.equal(verification.verifySecretMaterial({ source: canary }).status, "FAIL");
  assert.equal(verification.verifyDependencyReport({ lockfile_present: true, lockfile_integrity: true, vulnerabilities: [{ severity: "CRITICAL", id: "CVE-FAKE" }] }).status, "FAIL");
  assert.equal(verification.verifyMigrationPreflight({ sql: "drop table bookings;", recovery_required: true }).status, "FAIL");
  assert.equal(verification.verifyRuntimeProbe({ statusCode: 500 }).status, "FAIL");
  assert.equal(verification.verifyAccessibilityReport({ form_labels_ok: false }).status, "FAIL");
  assert.equal(verification.verifyVisualReport({ captures: [{ brokenLayout: true }] }).status, "FAIL");
  assert.equal(verification.verifyAcceptanceCase({ requirement_id: "R-1", steps: [{ passed: false }] }).status, "FAIL");
  assert.equal(verification.verifyDomainEvidence({ intended_domain: "a.example", observed_domain: "b.example", ownership_verified: true, dns_resolves: true, tls_valid: true, routing_correct: true, project_binding_correct: true }).status, "FAIL");
  assert.equal(verification.verifyArtifactIdentity({ built: D("a"), verified: D("b") }).status, "FAIL");
});
