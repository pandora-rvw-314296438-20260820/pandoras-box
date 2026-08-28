
"use strict";

const { DEFAULT_LIMITS } = require("./registry");
const { evidenceDescriptor, normalizeCheckOutcome, verificationCostTelemetry } = require("./execution");

function safeError(error) {
  const message = String(error?.message ?? "Verification executor failed.")
    .replace(/(?:gh[pousr]_|github_pat_|AIza|sk-|vc_)[A-Za-z0-9_-]{12,}/g, "[REDACTED]")
    .slice(0, 1000);
  return message || "Verification executor failed.";
}

class VerificationOrchestrator {
  constructor({ service, authorityToken, executors = {}, evidenceSink = null, clock = () => new Date(), limits = {} } = {}) {
    if (!service || typeof service.request_verification !== "function" || typeof service.record_check !== "function") throw new Error("verification orchestrator requires a Verification Engine service boundary");
    if (authorityToken == null) throw new Error("verification orchestrator requires sealed verifier authority");
    this.service = service;
    this.authorityToken = authorityToken;
    this.clock = clock;
    this.limits = Object.freeze({ ...DEFAULT_LIMITS, ...limits });
    this.evidenceSink = evidenceSink;
    this.executors = new Map();
    for (const [checkId, executor] of Object.entries(executors)) this.registerExecutor(checkId, executor);
  }

  registerExecutor(checkId, executor) {
    if (!executor || typeof executor.execute !== "function") throw new Error(`verification executor ${checkId} must expose execute()`);
    if (executor.independence !== "pandora_independent") throw new Error(`verification executor ${checkId} is not independent`);
    this.executors.set(checkId, Object.freeze({ ...executor }));
    return this;
  }

  async run(request, { requirements = [], context = {} } = {}) {
    const run = this.service.request_verification(request);
    this.service.start_verification(run.verification_run_id, this.authorityToken);
    const recorded = [];
    for (const checkId of run.required_checks) {
      const result = await this.#executeCheck(run, checkId, context);
      recorded.push(this.service.record_check(run.verification_run_id, this.authorityToken, result));
    }
    const final = this.service.finalize_verification(run.verification_run_id, this.authorityToken);
    return Object.freeze({ run: final, summary: this.service.get_release_readiness(run.verification_run_id, requirements), repair_feedback: this.service.get_repair_feedback(run.verification_run_id), cost_telemetry: verificationCostTelemetry(recorded) });
  }

  async #executeCheck(run, checkId, context) {
    const executor = this.executors.get(checkId);
    if (!executor) return normalizeCheckOutcome(checkId, { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Required independent verification executor is not configured." });
    const startedAt = this.clock();
    try {
      const raw = await executor.execute(Object.freeze({ check_id: checkId, request: run.request, identity_digest: run.identity_digest, limits: this.limits, context: Object.freeze({ ...context }), credentials: Object.freeze({ provider_master_credentials: false, builder_credentials: false }), browser_content_trust: "untrusted" }));
      const elapsed = Math.max(0, this.clock().getTime() - startedAt.getTime());
      const evidenceRefs = [];
      let evidenceBytes = 0;
      for (const item of (raw?.evidence ?? []).slice(0, 100)) {
        const serialized = JSON.stringify(item.data ?? null);
        evidenceBytes += Buffer.byteLength(serialized, "utf8");
        if (evidenceBytes > this.limits.maxEvidenceBytes) return normalizeCheckOutcome(checkId, { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Verification evidence exceeded resource limit." });
        const descriptor = evidenceDescriptor({ type: item.type ?? checkId, data: item.data ?? null, mediaType: item.media_type ?? "application/json", storageRef: item.storage_ref ?? null, createdAt: this.clock().toISOString() });
        const ref = this.evidenceSink?.store ? await this.evidenceSink.store(descriptor, item.data ?? null, { run, checkId }) : `sha256:${descriptor.content_sha256}`;
        evidenceRefs.push(String(ref));
      }
      const outcome = normalizeCheckOutcome(checkId, { ...(raw ?? {}), duration_ms: raw?.duration_ms ?? elapsed, evidence_refs: evidenceRefs });
      if (outcome.duration_ms > this.limits.maxCheckDurationMs) return normalizeCheckOutcome(checkId, { status: "BLOCKED", failure_class: "verification_infrastructure", summary: "Verification executor exceeded resource limit.", duration_ms: outcome.duration_ms });
      return outcome;
    } catch (error) {
      return normalizeCheckOutcome(checkId, { status: "BLOCKED", failure_class: "verification_infrastructure", summary: safeError(error), duration_ms: Math.max(0, this.clock().getTime() - startedAt.getTime()) });
    }
  }
}

function independentExecutor(execute, metadata = {}) {
  if (typeof execute !== "function") throw new Error("independent executor requires execute function");
  return Object.freeze({ independence: "pandora_independent", execute, ...metadata });
}

function builderReceiptExecutor() {
  return Object.freeze({ independence: "builder_report", execute: async () => ({ status: "PASS" }) });
}

module.exports = { VerificationOrchestrator, independentExecutor, builderReceiptExecutor };
