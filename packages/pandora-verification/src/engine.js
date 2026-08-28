"use strict";

const { randomUUID } = require("node:crypto");
const {
  CHECK_STATUSES, assertExactVerificationRequest, identityDigest, requirementCoverage, repairFeedback,
} = require("./contracts");
const { CHECK_REGISTRY, PROFILES, DEFAULT_LIMITS } = require("./registry");
const { cacheKeyForCheck } = require("./checks");

function snapshot(value) {
  return JSON.parse(JSON.stringify(value));
}

function releaseReadiness(run, requirements = []) {
  const required = run.required_checks ?? [];
  const results = run.results ?? [];
  const failed = results.filter((result) => result.status === "FAIL").map((result) => result.check_id);
  const blocked = results.filter((result) => ["BLOCKED", "INCONCLUSIVE"].includes(result.status)).map((result) => result.check_id);
  const missing = required.filter((id) => !results.some((result) => result.check_id === id));
  const publishEligible = run.status === "PASS" && !run.invalidated_at && !failed.length && !blocked.length && !missing.length;
  return Object.freeze({
    verification_run_id: run.verification_run_id,
    project_spec_id: run.request.project_spec_id,
    project_spec_version: run.request.project_spec_version ?? null,
    project_version_id: run.request.project_version_id,
    source_commit: run.request.source_commit,
    source_digest: run.request.source_digest,
    artifact_digest: run.request.artifact_digest,
    verification: run.status,
    required_checks: [...required],
    failed_checks: failed,
    blocked_checks: blocked,
    missing_checks: missing,
    requirement_coverage: requirementCoverage(requirements, results),
    publish_eligible: publishEligible,
    evidence_refs: [...new Set(results.flatMap((result) => result.evidence_refs ?? []))],
  });
}

function simpleProjection(run, productionVerified = false) {
  if (productionVerified) return "live_and_verified";
  if (releaseReadiness(run).publish_eligible) return "verified";
  if (["PENDING", "RUNNING"].includes(run.status)) return "checking";
  if (run.status === "BLOCKED") return "blocked";
  if (["FAIL", "INCONCLUSIVE", "STALE"].includes(run.status)) return "needs_fix";
  return run.status === "PASS" ? "verified" : "checking";
}

class VerificationEngine {
  #runs = new Map();
  #authorityToken;
  #trustedIssuer;

  constructor(options = {}) {
    this.#authorityToken = options.authorityToken ?? Symbol("sealed-verifier-authority");
    this.#trustedIssuer = options.trustedIssuer ?? "pandora-verification-engine";
    this.clock = options.clock ?? (() => new Date());
    this.limits = Object.freeze({ ...DEFAULT_LIMITS, ...(options.limits ?? {}) });
  }

  requestVerification(request) {
    assertExactVerificationRequest(request, PROFILES);
    const verificationRunId = request.verification_run_id ?? randomUUID();
    if (this.#runs.has(verificationRunId)) throw new Error("verification run already exists");
    const createdAt = request.created_at ?? this.clock().toISOString();
    const normalizedRequest = Object.freeze({ ...request, verification_run_id: verificationRunId, created_at: createdAt });
    const run = {
      verification_run_id: verificationRunId,
      request: normalizedRequest,
      identity_digest: identityDigest(normalizedRequest, PROFILES),
      required_checks: [...PROFILES[request.required_check_profile].requiredChecks],
      status: "PENDING",
      results: [],
      created_at: createdAt,
      started_at: null,
      completed_at: null,
      invalidated_at: null,
      invalidation_reason: null,
      retry_of: request.retry_of ?? null,
    };
    this.#runs.set(verificationRunId, run);
    return snapshot(run);
  }

  getVerification(runId) {
    return snapshot(this.#requireRun(runId));
  }

  start(runId, authorityToken) {
    this.#assertTrusted(authorityToken);
    const run = this.#requireRun(runId);
    if (run.status !== "PENDING") throw new Error(`verification run cannot start from ${run.status}`);
    run.status = "RUNNING";
    run.started_at = this.clock().toISOString();
    return snapshot(run);
  }

  recordCheck(runId, authorityToken, result) {
    this.#assertTrusted(authorityToken);
    const run = this.#requireRun(runId);
    if (run.invalidated_at) throw new Error("stale verification run cannot receive authoritative results");
    const definition = CHECK_REGISTRY[result?.check_id];
    if (!definition) throw new Error(`unknown verification check: ${result?.check_id}`);
    if (!CHECK_STATUSES.includes(result.status)) throw new Error(`invalid verification check status: ${result.status}`);
    if (result.status === "PASS" && result.authoritative === false) throw new Error("non-authoritative evidence cannot produce PASS");
    if (result.identity_digest && result.identity_digest !== run.identity_digest) throw new Error("verification result identity mismatch");
    if (result.duration_ms != null && result.duration_ms > this.limits.maxCheckDurationMs) throw new Error("verification check exceeded resource limit");
    const normalized = Object.freeze({
      check_id: result.check_id,
      category: definition.category,
      status: result.status,
      failure_class: result.failure_class ?? (result.status === "PASS" ? null : definition.failureClass),
      severity: result.severity ?? null,
      summary: result.summary ?? null,
      requirement_id: result.requirement_id ?? null,
      acceptance_criterion_id: result.acceptance_criterion_id ?? null,
      evidence_refs: [...(result.evidence_refs ?? [])],
      command: result.command ?? null,
      tool: result.tool ?? null,
      tool_version: result.tool_version ?? null,
      duration_ms: result.duration_ms ?? null,
      cache_key: result.cache_key ?? cacheKeyForCheck(result.check_id, run.request, run.identity_digest),
      expires_at: result.expires_at ?? null,
      identity_digest: run.identity_digest,
      recorded_at: this.clock().toISOString(),
      authoritative_issuer: this.#trustedIssuer,
    });
    const existing = run.results.findIndex((item) => item.check_id === normalized.check_id && item.requirement_id === normalized.requirement_id && item.acceptance_criterion_id === normalized.acceptance_criterion_id);
    if (existing >= 0) run.results[existing] = normalized;
    else run.results.push(normalized);
    return normalized;
  }

  finalize(runId, authorityToken) {
    this.#assertTrusted(authorityToken);
    const run = this.#requireRun(runId);
    if (run.invalidated_at) {
      run.status = "STALE";
      run.completed_at = this.clock().toISOString();
      return snapshot(run);
    }
    const requiredResults = run.required_checks.map((id) => run.results.filter((result) => result.check_id === id));
    if (requiredResults.some((results) => results.length === 0)) run.status = "INCONCLUSIVE";
    else {
      const all = requiredResults.flat();
      if (all.some((result) => result.status === "FAIL")) run.status = "FAIL";
      else if (all.some((result) => result.status === "BLOCKED")) run.status = "BLOCKED";
      else if (all.some((result) => ["INCONCLUSIVE", "SKIPPED"].includes(result.status))) run.status = "INCONCLUSIVE";
      else if (all.every((result) => result.status === "PASS")) run.status = "PASS";
      else run.status = "INCONCLUSIVE";
    }
    run.completed_at = this.clock().toISOString();
    return snapshot(run);
  }

  invalidate(runId, reason, authorityToken) {
    this.#assertTrusted(authorityToken);
    return this.#invalidate(runId, reason);
  }

  assertIdentityCurrent(runId, currentRequest) {
    const run = this.#requireRun(runId);
    const current = identityDigest(currentRequest, PROFILES);
    if (current !== run.identity_digest) {
      this.#invalidate(runId, "immutable verification identity changed");
      return false;
    }
    return true;
  }

  retry(runId, overrides = {}) {
    const prior = this.#requireRun(runId);
    return this.requestVerification({
      ...prior.request, ...overrides,
      verification_run_id: overrides.verification_run_id ?? randomUUID(),
      retry_of: runId,
      created_at: this.clock().toISOString(),
    });
  }

  getRequirementCoverage(runId, requirements) {
    return requirementCoverage(requirements, this.#requireRun(runId).results);
  }

  getVerificationSummary(runId, requirements = []) {
    return releaseReadiness(this.#requireRun(runId), requirements);
  }

  getReleaseReadiness(runId, requirements = []) {
    return this.getVerificationSummary(runId, requirements);
  }

  getRepairFeedback(runId) {
    return this.#requireRun(runId).results.filter((result) => result.status !== "PASS").map(repairFeedback);
  }

  #invalidate(runId, reason) {
    if (typeof reason !== "string" || !reason.trim()) throw new Error("invalidation reason is required");
    const run = this.#requireRun(runId);
    if (!run.invalidated_at) {
      run.invalidated_at = this.clock().toISOString();
      run.invalidation_reason = reason;
      run.status = "STALE";
    }
    return snapshot(run);
  }

  #requireRun(runId) {
    const run = this.#runs.get(runId);
    if (!run) throw new Error("verification run not found");
    return run;
  }

  #assertTrusted(authorityToken) {
    if (authorityToken !== this.#authorityToken) {
      throw new Error("authoritative verification state may only be written by the trusted Verification Engine executor");
    }
  }
}

module.exports = { VerificationEngine, releaseReadiness, simpleProjection };
