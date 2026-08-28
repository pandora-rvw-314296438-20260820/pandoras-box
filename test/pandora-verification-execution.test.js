
"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");

const D = (ch) => ch.repeat(64);
const C = (ch) => ch.repeat(40);

test("independent command plans never carry standing provider secrets", () => {
  const plan = verification.createIndependentCommandPlan({ checkId: "source_lint", executable: "npm", args: ["run", "lint"] });
  assert.equal(plan.shell, false);
  assert.equal(plan.persist_credentials, false);
  assert.equal(plan.network, "deny_by_default");
  assert.throws(() => verification.createIndependentCommandPlan({ checkId: "source_lint", executable: "npm", env: { GITHUB_TOKEN: "fake" } }), /standing secret/);
});

test("project-provided tests remain untrusted and cannot be release authority", () => {
  const plan = verification.createProjectTestPlan({ checkId: "unit_tests", testDefinitionId: "project-unit-suite" });
  assert.equal(plan.trust, "project_untrusted");
  assert.equal(plan.authoritative_for_release, false);
  assert.equal(plan.provider_credentials, "none");
});

test("verification logs redact fake canary values", () => {
  const canary = "PANDORA_CANARY_SECRET_FAKE123456789";
  const text = verification.redactText(`before=${canary};after=ok`);
  assert.doesNotMatch(text, new RegExp(canary));
  assert.match(text, /\[REDACTED\]/);
});

test("dependency severity is separated from Worker C policy decision", () => {
  const high = verification.verifyDependencyReport({ lockfile_present: true, lockfile_integrity: true, vulnerabilities: [{ id: "CVE-FAKE", severity: "HIGH" }] });
  const medium = verification.verifyDependencyReport({ lockfile_present: true, lockfile_integrity: true, vulnerabilities: [{ id: "CVE-REVIEW", severity: "MEDIUM" }] });
  assert.equal(high.status, "FAIL");
  assert.equal(medium.status, "PASS");
  assert.equal(medium.policy_signal.review.length, 1);
});

test("reviewed security exceptions are exact, version-bound and expiring", () => {
  const finding = { code: "fake", severity: "HIGH", fingerprint: "abc123" };
  const active = verification.applyReviewedExceptions([finding], [{ exception_id: "ex1", finding_fingerprint: "abc123", project_version_id: "v1", approved_by: "reviewer", reason: "false positive", expires_at: "2030-01-01T00:00:00Z" }], { versionId: "v1", now: Date.parse("2026-08-29T00:00:00Z") });
  const wrongVersion = verification.applyReviewedExceptions([finding], [{ exception_id: "ex1", finding_fingerprint: "abc123", project_version_id: "v1", approved_by: "reviewer", reason: "false positive", expires_at: "2030-01-01T00:00:00Z" }], { versionId: "v2", now: Date.parse("2026-08-29T00:00:00Z") });
  assert.equal(active[0].excepted, true);
  assert.equal(wrongVersion[0].excepted, false);
});

test("accessibility proof fails missing labels, touch targets and text scaling", () => {
  const broken = verification.verifyAccessibilityReport({ form_labels_ok: false, invalid_touch_targets: 2, text_scaling_ok: false });
  const accessible = verification.verifyAccessibilityReport({ semantic_structure_ok: true, form_labels_ok: true, screen_reader_structure_ok: true, text_scaling_ok: true, invalid_touch_targets: 0, keyboard_navigation_ok: true, contrast_ok: true, reduced_motion_ok: true });
  assert.equal(broken.status, "FAIL");
  assert.equal(accessible.status, "PASS");
});

test("visual policy distinguishes approved/review/broken changes", () => {
  assert.equal(verification.verifyVisualReport({ captures: [{ changedPixelRatio: 0.001 }] }).status, "PASS");
  assert.equal(verification.verifyVisualReport({ captures: [{ changedPixelRatio: 0.01 }] }).status, "INCONCLUSIVE");
  assert.equal(verification.verifyVisualReport({ captures: [{ brokenLayout: true }] }).status, "FAIL");
});

test("migration safety proves preflight and postflight separately", () => {
  const safe = verification.verifyMigrationPreflight({ sql: "alter table bookings add column note text;", rollback_plan_ref: "rollback-1", order_valid: true, backward_compatible: true, rls_policy_valid: true });
  const destructive = verification.verifyMigrationPreflight({ sql: "drop table bookings;", recovery_required: true });
  const mismatch = verification.verifyDatabasePostflight({ intended_schema_digest: D("a"), actual_schema_digest: D("b"), critical_data_accessible: true, constraints_ok: true, indexes_ok: true, rls_policies_ok: true, application_compatible: true });
  assert.equal(safe.status, "PASS");
  assert.equal(destructive.status, "FAIL");
  assert.equal(mismatch.status, "FAIL");
});

test("browser verifier evaluates running journeys rather than source HTML", () => {
  const good = verification.verifyBrowserReport({ page_loaded: true, navigation_ok: true, journeys: [{ requirement_id: "R-1", acceptance_criterion_id: "AC-1", passed: true, fatal_console_errors: 0 }] });
  const bad = verification.verifyBrowserReport({ page_loaded: true, navigation_ok: true, journeys: [{ requirement_id: "R-1", passed: true, fatal_console_errors: 1 }] });
  assert.equal(good.status, "PASS");
  assert.equal(bad.status, "FAIL");
});

test("acceptance results preserve ProjectSpec requirement and criterion IDs", () => {
  const result = verification.verifyAcceptanceCase({ requirement_id: "R-14", acceptance_criterion_id: "AC-3", steps: [{ id: "visible", passed: true }, { id: "persisted", passed: true }] });
  assert.equal(result.status, "PASS");
  assert.equal(result.requirement_id, "R-14");
  assert.equal(result.acceptance_criterion_id, "AC-3");
});

test("business acceptance verifies measurement capability without claiming outcome", () => {
  assert.equal(verification.verifyAnalyticsInstrumentation({ requiredEvents: ["completed_booking"], implementedEvents: [] }).status, "FAIL");
  assert.equal(verification.verifyAnalyticsInstrumentation({ requiredEvents: ["completed_booking"], implementedEvents: ["completed_booking"] }).status, "PASS");
});

test("preview verification requires exact version, source and artifact plus runtime health", () => {
  const request = { artifact_digest: D("a"), source_commit: C("b"), project_version_id: "v1" };
  const pass = verification.verifyPreviewEvidence({ request, deployment: { artifact_digest: D("a"), source_commit: C("b"), project_version_id: "v1", provider_status: "READY", deployment_id: "preview-1", url: "https://preview.invalid" }, probes: [{ statusCode: 200 }] });
  const mismatch = verification.verifyPreviewEvidence({ request, deployment: { artifact_digest: D("c"), source_commit: C("b"), project_version_id: "v1", provider_status: "READY" }, probes: [{ statusCode: 200 }] });
  assert.equal(pass.status, "PASS");
  assert.equal(mismatch.status, "FAIL");
});

test("production verification requires exact deployment, domain and runtime smoke", () => {
  const request = { artifact_digest: D("a"), source_commit: C("b"), project_version_id: "v1" };
  const pass = verification.verifyProductionEvidence({ request, deployment: { artifact_digest: D("a"), source_commit: C("b"), project_version_id: "v1", deployment_id: "prod-1", url: "https://app.example" }, domain: { intended_domain: "app.example", observed_domain: "app.example", ownership_verified: true, dns_resolves: true, tls_valid: true, routing_correct: true, project_binding_correct: true }, probes: [{ statusCode: 200 }] });
  assert.equal(pass.status, "PASS");
});

test("Control Plane mapping refuses builder/verifier identity collapse", () => {
  assert.throws(() => verification.assertIndependentIdentity("worker-d", "worker-d"), /independent/);
  assert.equal(verification.assertIndependentIdentity("worker-d", "worker-e"), true);
});

test("orchestrator refuses builder report as authoritative executor", () => {
  const service = { request_verification() {}, record_check() {} };
  assert.throws(() => new verification.VerificationOrchestrator({ service, authorityToken: {}, executors: { source_lint: verification.builderReceiptExecutor() } }), /not independent/);
});

test("orchestrator emits blocked state when required independent executor is absent", async () => {
  let recorded;
  const service = { request_verification: (request) => ({ verification_run_id: "run-1", request, identity_digest: D("f"), required_checks: ["source_lint"], status: "PENDING" }), start_verification: () => {}, record_check: (_runId, _actor, result) => (recorded = result), finalize_verification: () => ({ status: "BLOCKED" }), get_release_readiness: () => ({ publish_eligible: false }), get_repair_feedback: () => [{ check: "source_lint" }] };
  const orchestrator = new verification.VerificationOrchestrator({ service, authorityToken: {} });
  const result = await orchestrator.run({ project_version_id: "v1" });
  assert.equal(recorded.status, "BLOCKED");
  assert.equal(recorded.failure_class, "verification_infrastructure");
  assert.equal(result.summary.publish_eligible, false);
});

test("orchestrator digests evidence and does not put binary evidence in run state", async () => {
  let recorded;
  const service = { request_verification: (request) => ({ verification_run_id: "run-1", request, identity_digest: D("f"), required_checks: ["source_lint"], status: "PENDING" }), start_verification: () => {}, record_check: (_runId, _actor, result) => (recorded = result), finalize_verification: () => ({ status: "PASS" }), get_release_readiness: () => ({ publish_eligible: true }), get_repair_feedback: () => [] };
  const orchestrator = new verification.VerificationOrchestrator({ service, authorityToken: {}, executors: { source_lint: verification.independentExecutor(async () => ({ status: "PASS", evidence: [{ type: "lint-report", data: { pass: 12, fail: 0 } }] })) } });
  await orchestrator.run({ project_version_id: "v1" });
  assert.match(recorded.evidence_refs[0], /^sha256:[0-9a-f]{64}$/);
});


test("preview and production fail closed when provider artifact identity is unavailable", () => {
  const request = { artifact_digest: D("a"), source_commit: C("b"), project_version_id: "v1" };
  assert.equal(verification.verifyPreviewEvidence({ request, deployment: { source_commit: C("b"), project_version_id: "v1", provider_status: "READY" }, probes: [{ statusCode: 200 }] }).status, "BLOCKED");
  assert.equal(verification.verifyProductionEvidence({ request, deployment: { source_commit: C("b"), project_version_id: "v1" }, domain: { intended_domain: "app.example", observed_domain: "app.example", ownership_verified: true, dns_resolves: true, tls_valid: true, routing_correct: true, project_binding_correct: true }, probes: [{ statusCode: 200 }] }).status, "BLOCKED");
});
