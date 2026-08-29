
"use strict";

const contracts = require("./contracts");
const registry = require("./registry");
const checks = require("./checks");
const engine = require("./engine");
const execution = require("./execution");
const orchestrator = require("./orchestrator");
const controlPlane = require("./control-plane");
const freshness = require("./freshness");
const workerAdapters = require("./worker-adapters");
const reports = require("./reports");\nconst primitiveTrust = require("./primitive-trust");

function createVerificationService(options = {}) {
  const verifier = new engine.VerificationEngine(options);
  return Object.freeze({
    request_verification: (request) => verifier.requestVerification(request),
    get_verification: (runId) => verifier.getVerification(runId),
    get_verification_summary: (runId, requirements = []) => verifier.getVerificationSummary(runId, requirements),
    get_requirement_coverage: (runId, requirements = []) => verifier.getRequirementCoverage(runId, requirements),
    get_release_readiness: (runId, requirements = []) => verifier.getReleaseReadiness(runId, requirements),
    get_verification_freshness: (runId) => verifier.getVerificationFreshness(runId),
    get_repair_feedback: (runId) => verifier.getRepairFeedback(runId),
    start_verification: (runId, actor) => verifier.start(runId, actor),
    record_check: (runId, actor, result) => verifier.recordCheck(runId, actor, result),
    finalize_verification: (runId, actor) => verifier.finalize(runId, actor),
    invalidate_verification: (runId, reason, actor) => verifier.invalidate(runId, reason, actor),
    assert_identity_current: (runId, request, actor) => verifier.assertIdentityCurrent(runId, request, actor),
    retry_verification: (runId, overrides = {}) => verifier.retry(runId, overrides),
    _engine: verifier,
  });
}

module.exports = Object.freeze({ ...contracts, ...registry, ...checks, ...engine, ...execution, ...orchestrator, ...controlPlane, ...freshness, ...workerAdapters, ...reports, ...primitiveTrust, createVerificationService });
