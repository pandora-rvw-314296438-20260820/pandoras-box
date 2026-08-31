"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");

const D = (ch) => ch.repeat(64);
const C = (ch) => ch.repeat(40);

function request(overrides = {}) {
  return {
    verification_run_id: "run-1",
    organization_id: "org-1",
    project_id: "project-1",
    project_spec_id: "spec-1",
    project_spec_version: 12,
    project_version_id: "version-18",
    source_commit: C("a"),
    source_digest: D("b"),
    artifact_digest: D("c"),
    migration_set_digest: D("d"),
    preview_deployment_id: "preview-18",
    target_environment: "preview",
    runtime_target_digest: D("e"),
    required_check_profile: "static_site",
    requested_by: "worker-j",
    ...overrides,
  };
}

function harness(overrides = {}) {
  const authorityToken = Object.freeze({ role: "trusted-verifier-executor" });
  const engine = new verification.VerificationEngine({
    authorityToken,
    clock: () => new Date("2026-08-28T16:00:00.000Z"),
    ...overrides,
  });
  return { authorityToken, engine };
}

function passRequired(engine, authorityToken, runId) {
  const run = engine.getVerification(runId);
  for (const checkId of run.required_checks) {
    engine.recordCheck(runId, authorityToken, {
      check_id: checkId,
      status: "PASS",
      evidence_refs: [`evidence:${checkId}`],
      duration_ms: 1,
    });
  }
}

test("registry covers every required profile check", () => {
  assert.equal(verification.validateRegistry(), true);
  for (const profile of Object.values(verification.PROFILES)) {
    assert.ok(profile.requiredChecks.length > 0);
    assert.ok(profile.requiredChecks.every((id) => verification.CHECK_REGISTRY[id]));
  }
});

test("verification request fails closed without exact immutable identity", () => {
  const { engine } = harness();
  assert.throws(() => engine.requestVerification(request({ artifact_digest: "latest" })), /64-hex/);
  assert.throws(() => engine.requestVerification(request({ source_commit: "abc123" })), /40-hex/);
  assert.throws(() => engine.requestVerification(request({ project_spec_id: "" })), /required/);
  assert.throws(() => engine.requestVerification(request({ required_check_profile: "easy_mode" })), /unknown check profile/);
});

test("builder, model, and client cannot forge authoritative PASS", () => {
  const { engine } = harness();
  const run = engine.requestVerification(request());
  for (const forgedAuthority of ["pandora-verification-engine", { role: "builder" }, null, undefined]) {
    assert.throws(
      () => engine.recordCheck(run.verification_run_id, forgedAuthority, { check_id: "source_lint", status: "PASS" }),
      /trusted Verification Engine executor/,
    );
  }
  assert.equal(engine.getVerification(run.verification_run_id).status, "PENDING");
});

test("builder, model, and client cannot forge verification invalidation", () => {
  const { engine } = harness();
  const run = engine.requestVerification(request());
  for (const forgedAuthority of ["pandora-verification-engine", { role: "builder" }, null, undefined]) {
    assert.throws(
      () => engine.assertIdentityCurrent(run.verification_run_id, request({ artifact_digest: D("f") }), forgedAuthority),
      /trusted Verification Engine executor/,
    );
  }
  assert.equal(engine.getVerification(run.verification_run_id).status, "PENDING");
});

test("trusted verifier can produce PASS only after every profile requirement passes", () => {
  const { engine, authorityToken } = harness();
  const run = engine.requestVerification(request());
  engine.start(run.verification_run_id, authorityToken);
  passRequired(engine, authorityToken, run.verification_run_id);
  const final = engine.finalize(run.verification_run_id, authorityToken);
  assert.equal(final.status, "PASS");
  assert.equal(engine.getReleaseReadiness(run.verification_run_id).publish_eligible, true);
});

test("missing required check is INCONCLUSIVE, never PASS", () => {
  const { engine, authorityToken } = harness();
  const run = engine.requestVerification(request());
  engine.start(run.verification_run_id, authorityToken);
  engine.recordCheck(run.verification_run_id, authorityToken, { check_id: "source_format", status: "PASS" });
  assert.equal(engine.finalize(run.verification_run_id, authorityToken).status, "INCONCLUSIVE");
  assert.equal(engine.getReleaseReadiness(run.verification_run_id).publish_eligible, false);
});

test("product failure differs from verifier infrastructure blockage", () => {
  const fail = verification.verifyRuntimeProbe({ statusCode: 500, expectedStatuses: [200] });
  const blocked = verification.verifyRuntimeProbe({ infrastructure_error: true, summary: "preview provider unavailable" });
  assert.equal(fail.status, "FAIL");
  assert.equal(fail.failure_class, "runtime");
  assert.equal(blocked.status, "BLOCKED");
  assert.equal(blocked.failure_class, "verification_infrastructure");
});

test("exact artifact mismatch invalidates previous verification eligibility", () => {
  const { engine, authorityToken } = harness();
  const run = engine.requestVerification(request());
  engine.start(run.verification_run_id, authorityToken);
  passRequired(engine, authorityToken, run.verification_run_id);
  engine.finalize(run.verification_run_id, authorityToken);
  assert.equal(engine.assertIdentityCurrent(run.verification_run_id, request({ artifact_digest: D("f") }), authorityToken), false);
  assert.equal(engine.getVerification(run.verification_run_id).status, "STALE");
  assert.equal(engine.getReleaseReadiness(run.verification_run_id).publish_eligible, false);
});

test("repair creates a new verification run and preserves historical failure", () => {
  const { engine, authorityToken } = harness();
  const first = engine.requestVerification(request());
  engine.start(first.verification_run_id, authorityToken);
  for (const checkId of first.required_checks) {
    engine.recordCheck(first.verification_run_id, authorityToken, {
      check_id: checkId,
      status: checkId === "runtime_health" ? "FAIL" : "PASS",
      summary: checkId === "runtime_health" ? "HTTP 500" : null,
      evidence_refs: [`evidence:${checkId}`],
    });
  }
  assert.equal(engine.finalize(first.verification_run_id, authorityToken).status, "FAIL");
  const second = engine.retry(first.verification_run_id, {
    verification_run_id: "run-2",
    project_version_id: "version-19",
    source_commit: C("9"),
    source_digest: D("8"),
    artifact_digest: D("7"),
    preview_deployment_id: "preview-19",
  });
  assert.equal(second.retry_of, first.verification_run_id);
  assert.equal(engine.getVerification(first.verification_run_id).status, "FAIL");
  assert.equal(second.status, "PENDING");
});

test("secret scanner detects fake canary but does not return its plaintext", () => {
  const canary = "PANDORA_CANARY_SECRET_FAKE123456789";
  const result = verification.scanSecrets(`fixture=${canary}`);
  assert.equal(result.status, "FAIL");
  assert.ok(result.findings.some((finding) => finding.kind === "pandora_canary"));
  assert.doesNotMatch(JSON.stringify(result), new RegExp(canary));
  assert.ok(result.findings.every((finding) => finding.redacted === "[REDACTED]"));
});

test("migration verification rejects destructive SQL without recovery context", () => {
  const safe = verification.analyzeMigrationSql("alter table bookings add column note text;", { rollbackPlan: "drop-added-column" });
  const destructive = verification.analyzeMigrationSql("drop table bookings;");
  assert.equal(safe.status, "PASS");
  assert.equal(destructive.status, "FAIL");
  assert.ok(destructive.findings.some((finding) => finding.code === "destructive_drop"));
  assert.ok(destructive.findings.some((finding) => finding.code === "rollback_plan_missing"));
});

test("artifact identity binds build, verification, preview, and production", () => {
  const digest = D("1");
  assert.equal(verification.verifyArtifactIdentity({ built: digest, verified: digest, preview: digest, production: digest }).status, "PASS");
  assert.equal(verification.verifyArtifactIdentity({ built: digest, verified: D("2"), preview: digest }).status, "FAIL");
});

test("evidence digest is deterministic and tamper evident", () => {
  const first = verification.createEvidence({ type: "unit-report", data: { pass: 9, fail: 0 } });
  const same = verification.createEvidence({ type: "unit-report", data: { fail: 0, pass: 9 } });
  const changed = verification.createEvidence({ type: "unit-report", data: { pass: 8, fail: 1 } });
  assert.equal(first.sha256, same.sha256);
  assert.notEqual(first.sha256, changed.sha256);
});

test("freshness cache is bound to exact verification identity", () => {
  const first = request();
  const second = request({ preview_deployment_id: "preview-19" });
  const firstIdentity = verification.identityDigest(first, verification.PROFILES);
  const secondIdentity = verification.identityDigest(second, verification.PROFILES);
  const firstKey = verification.cacheKeyForCheck("runtime_health", first, firstIdentity);
  const secondKey = verification.cacheKeyForCheck("runtime_health", second, secondIdentity);
  assert.notEqual(firstKey, secondKey);
  assert.equal(verification.canReuseCheck({ status: "PASS", cache_key: firstKey }, secondKey), false);
});

test("requirement coverage traces checks to ProjectSpec requirement IDs", () => {
  const coverage = verification.requirementCoverage(
    ["R-1", "R-2", "R-3"],
    [
      { check_id: "acceptance_requirements", requirement_id: "R-1", status: "PASS" },
      { check_id: "acceptance_requirements", requirement_id: "R-2", status: "FAIL" },
    ],
  );
  assert.deepEqual(coverage.map((item) => item.status), ["PASS", "FAIL", "NOT TESTABLE"]);
});

test("visual differences are classified against the requested outcome", () => {
  assert.equal(verification.classifyVisualDiff({ changedPixelRatio: 0.001 }), "EXPECTED CHANGE");
  assert.equal(verification.classifyVisualDiff({ changedPixelRatio: 0.01 }), "REVIEW REQUIRED");
  assert.equal(verification.classifyVisualDiff({ changedPixelRatio: 0.25 }), "UNEXPECTED CHANGE");
  assert.equal(verification.classifyVisualDiff({ brokenLayout: true }), "BROKEN LAYOUT");
  assert.equal(
    verification.classifyVisualDiff({ changedPixelRatio: 0.001, expectedChange: true }),
    "MISSING EXPECTED CHANGE",
  );
  assert.equal(
    verification.classifyVisualDiff({ changedPixelRatio: 0.25, expectedChange: true }),
    "EXPECTED CHANGE",
  );
});

test("production drift detection is explicit", () => {
  assert.equal(verification.detectProductionDrift({
    verifiedDeploymentId: "d1", currentDeploymentId: "d1",
    verifiedArtifactDigest: D("a"), currentArtifactDigest: D("a"),
  }), "verified_current");
  assert.equal(verification.detectProductionDrift({
    verifiedDeploymentId: "d1", currentDeploymentId: "d2",
    verifiedArtifactDigest: D("a"), currentArtifactDigest: D("a"),
  }), "drift_detected");
});

test("simple projection hides framework detail", () => {
  assert.equal(verification.simpleProjection({ status: "RUNNING", required_checks: [], results: [], request: {} }), "checking");
  assert.equal(verification.simpleProjection({ status: "FAIL", required_checks: [], results: [], request: {} }), "needs_fix");
  assert.equal(verification.simpleProjection({ status: "BLOCKED", required_checks: [], results: [], request: {} }), "blocked");
});

test("service boundary exposes stable read and execution contracts", () => {
  const authorityToken = {};
  const service = verification.createVerificationService({ authorityToken });
  const run = service.request_verification(request({ verification_run_id: "service-run" }));
  assert.equal(service.get_verification(run.verification_run_id).project_version_id, undefined);
  assert.equal(service.get_verification(run.verification_run_id).request.project_version_id, "version-18");
  assert.throws(() => service.record_check(run.verification_run_id, {}, { check_id: "source_lint", status: "PASS" }), /trusted Verification Engine executor/);
});


test("artifact snapshot verification identity is exact without source_commit", () => {
  const { engine } = harness();
  const snapshot = request({ source_kind: "artifact_snapshot", source_ref: "version-18", source_commit: null });
  const run = engine.requestVerification(snapshot);
  assert.equal(run.request.source_kind, "artifact_snapshot");
  assert.equal(run.request.source_ref, "version-18");
  assert.equal(run.request.source_commit, null);
  assert.throws(() => engine.requestVerification(request({ source_kind: "artifact_snapshot", source_ref: "version-18", source_commit: C("f") })), /must not carry source_commit/);
});
