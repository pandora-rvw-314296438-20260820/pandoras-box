
"use strict";

const { createEvidence, requireDigest, sha256 } = require("./contracts");
const { CHECK_REGISTRY, DEFAULT_LIMITS } = require("./registry");
const {
  analyzeMigrationSql,
  classifyVisualDiff,
  scanSecrets,
  securityPolicySignal,
  verifyArtifactIdentity,
  verifyRuntimeProbe,
} = require("./checks");

const RESULT_STATUSES = new Set(["PASS", "FAIL", "BLOCKED", "INCONCLUSIVE", "SKIPPED"]);
const SECRET_ENV_NAMES = /(?:TOKEN|SECRET|PASSWORD|PRIVATE_KEY|SERVICE_ROLE|API_KEY|AUTHORIZATION|COOKIE)/i;
const SAFE_EXECUTABLE = /^[A-Za-z0-9._/+:-]{1,200}$/;

function freezeCopy(value) {
  if (value == null) return value;
  return Object.freeze(JSON.parse(JSON.stringify(value)));
}

function assertPlainObject(name, value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object`);
}

function boundedString(value, maxBytes = DEFAULT_LIMITS.maxLogBytes) {
  const text = String(value ?? "");
  const bytes = Buffer.from(text, "utf8");
  if (bytes.length <= maxBytes) return text;
  return Buffer.concat([bytes.subarray(0, Math.max(0, maxBytes - 32)), Buffer.from("\n[TRUNCATED_BY_VERIFIER]")]).toString("utf8");
}

function redactText(input, maxBytes = DEFAULT_LIMITS.maxLogBytes) {
  let text = boundedString(input, maxBytes);
  const findings = [...scanSecrets(text).findings].sort((a, b) => b.index - a.index);
  for (const finding of findings) {
    text = `${text.slice(0, finding.index)}[REDACTED]${text.slice(finding.index + finding.length)}`;
  }
  return text;
}

function assertSafeArgv(executable, args = []) {
  if (typeof executable !== "string" || !SAFE_EXECUTABLE.test(executable) || executable.includes("..")) {
    throw new Error("verification command executable is not trusted");
  }
  if (!Array.isArray(args) || args.length > 128) throw new Error("verification command args are invalid");
  for (const arg of args) {
    if (typeof arg !== "string" || arg.includes("\0") || Buffer.byteLength(arg, "utf8") > 4096) {
      throw new Error("verification command arg is invalid");
    }
  }
  return true;
}

function assertSafeEnvironment(env = {}) {
  assertPlainObject("verification environment", env);
  for (const [name, value] of Object.entries(env)) {
    if (!/^[A-Z0-9_]{1,80}$/.test(name)) throw new Error("verification environment variable name is invalid");
    if (SECRET_ENV_NAMES.test(name)) throw new Error(`verification environment may not contain standing secret ${name}`);
    if (typeof value !== "string" || Buffer.byteLength(value, "utf8") > 4096) throw new Error("verification environment value is invalid");
  }
  return true;
}

function createIndependentCommandPlan({ checkId, executable, args = [], cwd = ".", env = {}, tool = null, toolVersion = null, timeoutMs = DEFAULT_LIMITS.maxCheckDurationMs }) {
  if (!CHECK_REGISTRY[checkId]) throw new Error(`unknown verification check: ${checkId}`);
  assertSafeArgv(executable, args);
  assertSafeEnvironment(env);
  if (typeof cwd !== "string" || !cwd || cwd.startsWith("/") || cwd.includes("..") || cwd.includes("\\")) {
    throw new Error("verification command cwd must be a workspace-relative path");
  }
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > DEFAULT_LIMITS.maxCheckDurationMs) {
    throw new Error("verification command timeout exceeds verifier limit");
  }
  return Object.freeze({ kind: "command", trust: "pandora_independent", check_id: checkId, executable, args: Object.freeze([...args]), cwd, env: Object.freeze({ ...env }), shell: false, persist_credentials: false, network: "deny_by_default", tool, tool_version: toolVersion, timeout_ms: timeoutMs });
}

function createProjectTestPlan({ checkId, testDefinitionId, sandboxProfile = "verification-untrusted-tests", timeoutMs = DEFAULT_LIMITS.maxCheckDurationMs }) {
  if (!CHECK_REGISTRY[checkId]) throw new Error(`unknown verification check: ${checkId}`);
  if (!["unit_tests", "integration_tests", "browser_e2e"].includes(checkId)) throw new Error("project test definitions are not valid for this check");
  if (typeof testDefinitionId !== "string" || !/^[A-Za-z0-9._:-]{1,160}$/.test(testDefinitionId)) throw new Error("invalid project test definition id");
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > DEFAULT_LIMITS.maxCheckDurationMs) throw new Error("project test timeout exceeds verifier limit");
  return Object.freeze({ kind: "project_test", trust: "project_untrusted", check_id: checkId, test_definition_id: testDefinitionId, sandbox_profile: sandboxProfile, timeout_ms: timeoutMs, secrets: "none", provider_credentials: "none", network: "deny_by_default", authoritative_for_release: false });
}

function normalizeCommandResult(checkId, raw, limits = DEFAULT_LIMITS) {
  assertPlainObject("command result", raw);
  if (!CHECK_REGISTRY[checkId]) throw new Error(`unknown verification check: ${checkId}`);
  const duration = Number(raw.duration_ms ?? 0);
  if (!Number.isFinite(duration) || duration < 0 || duration > limits.maxCheckDurationMs) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Verification command exceeded resource limit.", duration_ms: Math.max(0, duration || 0) };
  if (raw.infrastructure_error || raw.timed_out) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: raw.timed_out ? "Verification command timed out." : "Verification command infrastructure failed.", duration_ms: duration };
  const status = raw.exit_code === 0 ? "PASS" : "FAIL";
  return { status, failure_class: status === "PASS" ? null : CHECK_REGISTRY[checkId].failureClass, summary: status === "PASS" ? "Independent command completed successfully." : `Independent command exited with code ${raw.exit_code}.`, command: raw.command_label ?? null, tool: raw.tool ?? null, tool_version: raw.tool_version ?? null, duration_ms: duration, diagnostics: { stdout: redactText(raw.stdout ?? "", limits.maxLogBytes), stderr: redactText(raw.stderr ?? "", limits.maxLogBytes), report: freezeCopy(raw.report ?? null) } };
}

function verifyDependencyReport(report, policy = {}) {
  assertPlainObject("dependency report", report);
  if (report.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Dependency verifier unavailable." };
  const findings = [];
  if (report.lockfile_present === false) findings.push({ code: "lockfile_missing", severity: "HIGH", summary: "Required dependency lockfile is missing." });
  if (report.lockfile_integrity === false) findings.push({ code: "lockfile_integrity", severity: "HIGH", summary: "Dependency lockfile integrity check failed." });
  if (report.unexpected_drift === true) findings.push({ code: "dependency_drift", severity: "MEDIUM", summary: "Unexpected dependency drift detected." });
  for (const item of report.vulnerabilities ?? []) {
    const severity = String(item.severity ?? "INFO").toUpperCase();
    findings.push({ code: String(item.id ?? "dependency_vulnerability"), package: item.package ?? null, severity: ["INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"].includes(severity) ? severity : "INFO", summary: boundedString(item.summary ?? "Dependency vulnerability detected.", 1000) });
  }
  const signal = securityPolicySignal(findings, policy);
  return { status: signal.blocking.length ? "FAIL" : "PASS", failure_class: signal.blocking.length ? "dependency" : null, severity: signal.blocking[0]?.severity ?? signal.review[0]?.severity ?? null, summary: signal.blocking.length ? "Dependency policy has blocking findings." : signal.review.length ? "Dependency findings require policy review." : "Dependency verification passed.", findings, policy_signal: signal };
}

function applyReviewedExceptions(findings, exceptions = [], { versionId = null, now = Date.now() } = {}) {
  return (findings ?? []).map((finding) => {
    const fingerprint = finding.fingerprint ?? sha256(JSON.stringify(finding)).slice(0, 16);
    const exception = exceptions.find((item) => item && item.finding_fingerprint === fingerprint && (!item.project_version_id || item.project_version_id === versionId) && item.approved_by && item.reason && (!item.expires_at || new Date(item.expires_at).getTime() > now));
    return Object.freeze({ ...finding, fingerprint, excepted: Boolean(exception), exception_id: exception?.exception_id ?? null });
  });
}

function verifySecretMaterial({ source = "", artifact = "", exceptions = [], projectVersionId = null, now = Date.now() }) {
  const sourceFindings = scanSecrets(source).findings.map((finding) => ({ ...finding, location: "source" }));
  const artifactFindings = scanSecrets(artifact).findings.map((finding) => ({ ...finding, location: "artifact" }));
  const findings = applyReviewedExceptions([...sourceFindings, ...artifactFindings], exceptions, { versionId: projectVersionId, now });
  const active = findings.filter((finding) => !finding.excepted);
  return { status: active.length ? "FAIL" : "PASS", failure_class: active.length ? "security" : null, severity: active.some((finding) => finding.severity === "CRITICAL") ? "CRITICAL" : active[0]?.severity ?? null, summary: active.length ? "Secret material detected in exact source or artifact." : "No secret material detected.", findings };
}

function verifyAccessibilityReport(report) {
  assertPlainObject("accessibility report", report);
  if (report.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Accessibility verifier unavailable." };
  const violations = (report.violations ?? []).filter((item) => item && item.ignored !== true).map((item) => ({ rule: String(item.rule ?? "unknown"), severity: String(item.severity ?? "MEDIUM").toUpperCase(), summary: boundedString(item.summary ?? "Accessibility violation detected.", 1000), target: item.target ?? null }));
  const brokenScaling = report.text_scaling_ok === false;
  const badTouchTargets = Number(report.invalid_touch_targets ?? 0) > 0;
  const keyboardFailure = report.keyboard_navigation_ok === false;
  const semanticsFailure = report.semantic_structure_ok === false || report.form_labels_ok === false || report.screen_reader_structure_ok === false;
  const contrastFailure = report.contrast_ok === false;
  const reducedMotionFailure = report.reduced_motion_ok === false;
  const failed = violations.length > 0 || brokenScaling || badTouchTargets || keyboardFailure || semanticsFailure || contrastFailure || reducedMotionFailure;
  return { status: failed ? "FAIL" : "PASS", failure_class: failed ? "accessibility" : null, severity: failed ? "HIGH" : null, summary: failed ? "Accessibility requirements are not satisfied." : "Accessibility verification passed.", violations, checks: { text_scaling_ok: !brokenScaling, touch_targets_ok: !badTouchTargets, keyboard_navigation_ok: !keyboardFailure, semantic_structure_ok: !semanticsFailure, contrast_ok: !contrastFailure, reduced_motion_ok: !reducedMotionFailure } };
}

function verifyVisualReport(report) {
  assertPlainObject("visual report", report);
  if (report.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Visual verifier unavailable." };
  const captures = (report.captures ?? []).slice(0, DEFAULT_LIMITS.maxScreenshots).map((capture) => { const classification = classifyVisualDiff(capture); return Object.freeze({ viewport: capture.viewport ?? null, baseline_digest: capture.baseline_digest ?? null, screenshot_digest: capture.screenshot_digest ?? null, changed_pixel_ratio: Number(capture.changedPixelRatio ?? 0), classification, baseline_approval_id: capture.baseline_approval_id ?? null }); });
  const broken = captures.some((item) => ["BROKEN LAYOUT", "UNEXPECTED CHANGE"].includes(item.classification));
  const review = captures.some((item) => item.classification === "REVIEW REQUIRED");
  return { status: broken ? "FAIL" : review ? "INCONCLUSIVE" : "PASS", failure_class: broken || review ? "visual" : null, summary: broken ? "Visual verification found an unexpected or broken layout." : review ? "Visual verification requires reviewed baseline approval." : "Visual verification passed.", captures };
}

function verifyMigrationPreflight(plan) {
  assertPlainObject("migration plan", plan);
  const analyzed = analyzeMigrationSql(plan.sql ?? "", { rollbackPlan: plan.rollback_plan_ref ?? null });
  const findings = [...analyzed.findings];
  const add = (code, severity, summary) => findings.push({ code, severity, summary });
  if (plan.order_valid === false) add("migration_order", "HIGH", "Migration ordering is invalid.");
  if (plan.backward_compatible === false) add("backward_compatibility", "HIGH", "Migration is not backward compatible.");
  if (plan.rls_policy_valid === false) add("rls_policy", "CRITICAL", "Migration would leave required RLS or policy state invalid.");
  if (plan.backup_required && !plan.backup_snapshot_ref) add("backup_missing", "HIGH", "Required backup or snapshot reference is missing.");
  if (plan.recovery_required && !plan.rollback_plan_ref) add("recovery_missing", "HIGH", "Required rollback or recovery plan is missing.");
  const blocking = findings.filter((finding) => ["HIGH", "CRITICAL"].includes(finding.severity));
  return { status: blocking.length ? "FAIL" : "PASS", failure_class: blocking.length ? "migration" : null, severity: blocking[0]?.severity ?? null, summary: blocking.length ? "Migration preflight has blocking findings." : "Migration preflight passed.", findings };
}

function verifyDatabasePostflight(report) {
  assertPlainObject("database postflight", report);
  if (report.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Database postflight verifier unavailable." };
  if (report.intended_schema_digest && report.actual_schema_digest) { requireDigest("intended_schema_digest", report.intended_schema_digest); requireDigest("actual_schema_digest", report.actual_schema_digest); }
  const checks = { schema_matches: !report.intended_schema_digest || report.intended_schema_digest.toLowerCase() === report.actual_schema_digest?.toLowerCase(), critical_data_accessible: report.critical_data_accessible !== false, constraints_ok: report.constraints_ok !== false, indexes_ok: report.indexes_ok !== false, rls_policies_ok: report.rls_policies_ok !== false, application_compatible: report.application_compatible !== false };
  const failed = Object.values(checks).some((value) => !value);
  return { status: failed ? "FAIL" : "PASS", failure_class: failed ? "migration" : null, summary: failed ? "Database state does not match the verified post-migration contract." : "Database post-migration verification passed.", checks };
}

function verifyBrowserReport(report) {
  assertPlainObject("browser report", report);
  if (report.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Browser verifier unavailable." };
  const journeys = (report.journeys ?? []).map((journey) => ({ requirement_id: journey.requirement_id ?? null, acceptance_criterion_id: journey.acceptance_criterion_id ?? null, name: journey.name ?? null, passed: journey.passed === true, fatal_console_errors: Number(journey.fatal_console_errors ?? 0), trace_ref: journey.trace_ref ?? null, screenshot_refs: [...(journey.screenshot_refs ?? [])].slice(0, DEFAULT_LIMITS.maxScreenshots) }));
  const failed = report.page_loaded === false || report.navigation_ok === false || journeys.some((journey) => !journey.passed || journey.fatal_console_errors > 0);
  return { status: failed ? "FAIL" : "PASS", failure_class: failed ? "browser" : null, summary: failed ? "Browser verification failed a critical runtime journey." : "Browser verification passed.", journeys };
}

function verifyAcceptanceCase(testCase) {
  assertPlainObject("acceptance case", testCase);
  if (!testCase.requirement_id) throw new Error("acceptance case requires requirement_id");
  const steps = (testCase.steps ?? []).map((step) => ({ id: step.id ?? null, passed: step.passed === true, evidence_ref: step.evidence_ref ?? null }));
  const blocked = testCase.infrastructure_error === true;
  const passed = !blocked && steps.length > 0 && steps.every((step) => step.passed);
  return { status: blocked ? "BLOCKED" : passed ? "PASS" : "FAIL", failure_class: blocked ? "verification_infrastructure" : passed ? null : "acceptance", summary: blocked ? "Acceptance verifier unavailable." : passed ? "Acceptance criterion satisfied." : "Acceptance criterion not satisfied.", requirement_id: testCase.requirement_id, acceptance_criterion_id: testCase.acceptance_criterion_id ?? null, steps };
}

function verifyAnalyticsInstrumentation({ requiredEvents = [], implementedEvents = [], schemaValid = true, environment = null }) {
  const required = [...new Set(requiredEvents.map(String))];
  const implemented = new Set(implementedEvents.map(String));
  const missing = required.filter((event) => !implemented.has(event));
  const failed = !schemaValid || missing.length > 0;
  return { status: failed ? "FAIL" : "PASS", failure_class: failed ? "business_acceptance" : null, summary: failed ? "Required business measurement instrumentation is incomplete." : "Business measurement instrumentation is ready.", environment, required_events: required, missing_events: missing };
}

function verifyDomainEvidence(domain) {
  assertPlainObject("domain evidence", domain);
  if (domain.infrastructure_error) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Domain verifier unavailable." };
  const checks = { intended_domain: domain.intended_domain === domain.observed_domain, ownership_verified: domain.ownership_verified === true, dns_resolves: domain.dns_resolves === true, tls_valid: domain.tls_valid === true, routing_correct: domain.routing_correct === true, unexpected_redirect: domain.unexpected_redirect !== true, project_binding_correct: domain.project_binding_correct === true };
  const failed = Object.values(checks).some((value) => !value);
  return { status: failed ? "FAIL" : "PASS", failure_class: failed ? "domain" : null, summary: failed ? "Domain verification failed." : "Domain verification passed.", checks };
}

function verifyPreviewEvidence({ request, deployment, probes = [] }) {
  assertPlainObject("preview deployment evidence", deployment);
  const identity = verifyArtifactIdentity({ built: request.artifact_digest, verified: request.artifact_digest, preview: deployment.artifact_digest, lineage: deployment.reproducible_lineage ?? [] });
  const sourceMatches = deployment.source_commit === request.source_commit;
  const versionMatches = deployment.project_version_id === request.project_version_id;
  if (!sourceMatches || !versionMatches || identity.status !== "PASS") return { status: "FAIL", failure_class: "runtime", summary: "Preview deployment identity does not match the exact verification request.", identity, source_matches: sourceMatches, version_matches: versionMatches };
  if (deployment.provider_status !== "READY") return { status: deployment.provider_status ? "FAIL" : "BLOCKED", failure_class: deployment.provider_status ? "runtime" : "provider", summary: "Preview deployment is not provider-ready." };
  const runtime = probes.map(verifyRuntimeProbe);
  if (runtime.some((item) => item.status === "BLOCKED")) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Preview runtime verification is blocked.", runtime };
  if (runtime.some((item) => item.status !== "PASS")) return { status: "FAIL", failure_class: "runtime", summary: "Preview runtime probe failed.", runtime };
  return { status: "PASS", failure_class: null, summary: "Exact preview identity and runtime verified.", runtime, deployment_id: deployment.deployment_id, url: deployment.url };
}

function verifyProductionEvidence({ request, deployment, domain, probes = [] }) {
  assertPlainObject("production deployment evidence", deployment);
  const identity = verifyArtifactIdentity({ built: request.artifact_digest, verified: request.artifact_digest, production: deployment.artifact_digest, lineage: deployment.reproducible_lineage ?? [] });
  const exact = deployment.project_version_id === request.project_version_id && deployment.source_commit === request.source_commit && identity.status === "PASS";
  if (!exact) return { status: "FAIL", failure_class: "runtime", summary: "Production deployment does not match the approved exact version.", identity };
  const domainResult = verifyDomainEvidence(domain);
  if (domainResult.status !== "PASS") return { ...domainResult, summary: `Production ${domainResult.summary.toLowerCase()}` };
  const runtime = probes.map(verifyRuntimeProbe);
  if (runtime.some((item) => item.status === "BLOCKED")) return { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Production runtime verification is blocked.", runtime };
  if (runtime.some((item) => item.status !== "PASS")) return { status: "FAIL", failure_class: "runtime", summary: "Production runtime smoke test failed.", runtime };
  return { status: "PASS", failure_class: null, summary: "Exact production deployment, domain, and runtime verified.", runtime, deployment_id: deployment.deployment_id, url: deployment.url };
}

function evidenceDescriptor({ type, data, mediaType = "application/json", storageRef = null, createdAt }) {
  const evidence = createEvidence({ type, data, mediaType, createdAt });
  return Object.freeze({ evidence_id: evidence.evidence_id, evidence_type: evidence.type, media_type: evidence.media_type, content_sha256: evidence.sha256, storage_ref: storageRef, created_at: evidence.created_at });
}

function verificationCostTelemetry(results = []) {
  return Object.freeze({ check_count: results.length, duration_ms: results.reduce((sum, result) => sum + Number(result.duration_ms ?? 0), 0), browser_minutes: results.filter((result) => result.check_id === "browser_e2e").reduce((sum, result) => sum + Number(result.duration_ms ?? 0), 0) / 60000, screenshot_count: results.reduce((sum, result) => sum + Number(result.screenshot_count ?? 0), 0), evidence_bytes: results.reduce((sum, result) => sum + Number(result.evidence_bytes ?? 0), 0), external_scan_count: results.reduce((sum, result) => sum + Number(result.external_scan_count ?? 0), 0) });
}

function normalizeCheckOutcome(checkId, outcome) {
  if (!CHECK_REGISTRY[checkId]) throw new Error(`unknown verification check: ${checkId}`);
  assertPlainObject("verification outcome", outcome);
  const status = String(outcome.status ?? "INCONCLUSIVE").toUpperCase();
  if (!RESULT_STATUSES.has(status)) throw new Error(`invalid verification outcome status ${status}`);
  return Object.freeze({ check_id: checkId, status, failure_class: outcome.failure_class ?? (status === "PASS" ? null : CHECK_REGISTRY[checkId].failureClass), severity: outcome.severity ?? null, summary: boundedString(outcome.summary ?? "", 2000) || null, requirement_id: outcome.requirement_id ?? null, acceptance_criterion_id: outcome.acceptance_criterion_id ?? null, evidence_refs: Object.freeze([...(outcome.evidence_refs ?? [])]), command: outcome.command ?? null, tool: outcome.tool ?? null, tool_version: outcome.tool_version ?? null, duration_ms: Number(outcome.duration_ms ?? 0), expires_at: outcome.expires_at ?? null });
}

module.exports = { RESULT_STATUSES, boundedString, redactText, assertSafeArgv, assertSafeEnvironment, createIndependentCommandPlan, createProjectTestPlan, normalizeCommandResult, verifyDependencyReport, applyReviewedExceptions, verifySecretMaterial, verifyAccessibilityReport, verifyVisualReport, verifyMigrationPreflight, verifyDatabasePostflight, verifyBrowserReport, verifyAcceptanceCase, verifyAnalyticsInstrumentation, verifyDomainEvidence, verifyPreviewEvidence, verifyProductionEvidence, evidenceDescriptor, verificationCostTelemetry, normalizeCheckOutcome };
