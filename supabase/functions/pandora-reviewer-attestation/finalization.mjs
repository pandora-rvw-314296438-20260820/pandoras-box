const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;

function isRecord(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function expectedBindings(request, attestation) {
  const terminalStatus = request?.decision === "pass"
    ? "completed"
    : request?.decision === "fail"
    ? "failed"
    : "";
  const expected = {
    organizationId: request?.organizationId,
    dispatchId: request?.dispatchId,
    planId: request?.planId,
    verifierRuntimeProofId: request?.verifierRuntimeProofId,
    verificationEvidenceId: attestation?.verificationEvidenceId,
    workerEvidenceSha256: request?.workerEvidenceSha256,
    reviewArtifactSha256: request?.reviewArtifactSha256,
    signatureBasisSha256: attestation?.signatureBasisSha256,
    repository: request?.repository,
    exactSha: request?.exactSha,
    sourceTreeSha: request?.sourceTreeSha,
    terminalStatus,
  };
  if (
    !UUID.test(expected.organizationId) || !UUID.test(expected.dispatchId) ||
    !UUID.test(expected.planId) || !UUID.test(expected.verifierRuntimeProofId) ||
    !UUID.test(expected.verificationEvidenceId) ||
    !SHA256.test(expected.workerEvidenceSha256) ||
    !SHA256.test(expected.reviewArtifactSha256) ||
    !SHA256.test(expected.signatureBasisSha256) ||
    expected.repository !== "pandora-rvw-314296438-20260820/pandoras-box" ||
    !SHA40.test(expected.exactSha) || !SHA40.test(expected.sourceTreeSha) ||
    !terminalStatus || !isRecord(attestation) ||
    attestation.dispatchId !== expected.dispatchId ||
    attestation.planId !== expected.planId ||
    attestation.verifierRuntimeProofId !== expected.verifierRuntimeProofId ||
    attestation.workerEvidenceSha256 !== expected.workerEvidenceSha256 ||
    attestation.reviewArtifactSha256 !== expected.reviewArtifactSha256 ||
    attestation.decision !== expected.terminalStatus
  ) {
    throw new Error("REVIEW_ATTESTATION_BINDING_MISMATCH");
  }
  return Object.freeze(expected);
}

function terminalExecutionMatches(value, expected) {
  if (!isRecord(value) || !isRecord(value.args) || !isRecord(value.resultSummary)) {
    return false;
  }
  return value.planId === expected.planId &&
    value.dispatchId === expected.dispatchId &&
    value.planStatus === expected.terminalStatus &&
    value.dispatchStatus === expected.terminalStatus &&
    value.verifiedOutcome === expected.terminalStatus &&
    value.verifierRuntimeProofId === expected.verifierRuntimeProofId &&
    value.verificationEvidenceId === expected.verificationEvidenceId &&
    value.evidenceSha256 === expected.workerEvidenceSha256 &&
    value.args.repository === expected.repository &&
    value.args.exactSha === expected.exactSha &&
    value.resultSummary.repository === expected.repository &&
    value.resultSummary.exactSha === expected.exactSha &&
    value.resultSummary.sourceTreeSha === expected.sourceTreeSha &&
    typeof value.verifiedAt === "string" &&
    Number.isFinite(Date.parse(value.verifiedAt)) &&
    typeof value.completedAt === "string" &&
    Number.isFinite(Date.parse(value.completedAt));
}

async function finalizeAttestedWorkerReview({ request, attestation, adapter }) {
  const expected = expectedBindings(request, attestation);
  if (
    !adapter || typeof adapter.finalizeReview !== "function" ||
    typeof adapter.getExecution !== "function"
  ) {
    throw new Error("REVIEW_FINALIZATION_ADAPTER_UNAVAILABLE");
  }

  let mutationUncertain = false;
  let receipt = null;
  try {
    receipt = await adapter.finalizeReview({
      organizationId: expected.organizationId,
      dispatchId: expected.dispatchId,
      planId: expected.planId,
      verifierRuntimeProofId: expected.verifierRuntimeProofId,
      verificationEvidenceId: expected.verificationEvidenceId,
      decision: expected.terminalStatus,
    });
    if (
      !isRecord(receipt) || receipt.dispatchId !== expected.dispatchId ||
      receipt.planId !== expected.planId ||
      receipt.status !== expected.terminalStatus ||
      receipt.verificationEvidenceId !== expected.verificationEvidenceId ||
      typeof receipt.idempotentReplay !== "boolean"
    ) {
      mutationUncertain = true;
    }
  } catch {
    mutationUncertain = true;
  }

  let execution;
  try {
    execution = await adapter.getExecution({
      organizationId: expected.organizationId,
      planId: expected.planId,
    });
  } catch {
    throw new Error("REVIEW_FINALIZATION_AMBIGUOUS");
  }
  if (!terminalExecutionMatches(execution, expected)) {
    throw new Error("REVIEW_FINALIZATION_AMBIGUOUS");
  }

  return Object.freeze({
    dispatchId: expected.dispatchId,
    planId: expected.planId,
    status: expected.terminalStatus,
    verifierRuntimeProofId: expected.verifierRuntimeProofId,
    verificationEvidenceId: expected.verificationEvidenceId,
    verifiedAt: execution.verifiedAt,
    idempotentReplay: receipt?.idempotentReplay === true,
    reconciledAfterUncertainMutation: mutationUncertain,
  });
}

export {
  expectedBindings,
  finalizeAttestedWorkerReview,
  terminalExecutionMatches,
};
