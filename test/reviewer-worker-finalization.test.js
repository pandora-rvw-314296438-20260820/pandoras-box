"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const PLAN_ID = "8ec3acda-4fb7-48b2-81f4-6885c005f561";
const DISPATCH_ID = "a6402a8a-4cbb-4812-80be-640028c81c5b";
const PROOF_ID = "91183a83-6a4d-4f91-84b0-ffb46c59302d";
const EVIDENCE_ID = "aa97daaa-28d3-48c7-a137-cd50c17ad60d";
const EXACT_SHA = "a".repeat(40);
const SOURCE_TREE_SHA = "b".repeat(40);
const WORKER_EVIDENCE = "c".repeat(64);
const REVIEW_ARTIFACT = "d".repeat(64);
const SIGNATURE_BASIS = "e".repeat(64);

async function subject() {
  return import(
    "../supabase/functions/pandora-reviewer-attestation/finalization.mjs"
  );
}

function reviewerRequest(decision = "pass") {
  return {
    organizationId: ORGANIZATION_ID,
    dispatchId: DISPATCH_ID,
    planId: PLAN_ID,
    verifierRuntimeProofId: PROOF_ID,
    workerEvidenceSha256: WORKER_EVIDENCE,
    reviewArtifactSha256: REVIEW_ARTIFACT,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    exactSha: EXACT_SHA,
    sourceTreeSha: SOURCE_TREE_SHA,
    decision,
  };
}

function attestation(status = "completed") {
  return {
    dispatchId: DISPATCH_ID,
    planId: PLAN_ID,
    decision: status,
    verifierRuntimeProofId: PROOF_ID,
    verificationEvidenceId: EVIDENCE_ID,
    workerEvidenceSha256: WORKER_EVIDENCE,
    reviewArtifactSha256: REVIEW_ARTIFACT,
    signatureBasisSha256: SIGNATURE_BASIS,
  };
}

function terminal(status = "completed", overrides = {}) {
  return {
    planId: PLAN_ID,
    planStatus: status,
    dispatchId: DISPATCH_ID,
    dispatchStatus: status,
    args: { repository: "pandora-rvw-314296438-20260820/pandoras-box", exactSha: EXACT_SHA },
    resultSummary: {
      repository: "pandora-rvw-314296438-20260820/pandoras-box",
      exactSha: EXACT_SHA,
      sourceTreeSha: SOURCE_TREE_SHA,
    },
    evidenceSha256: WORKER_EVIDENCE,
    verifierRuntimeProofId: PROOF_ID,
    verificationEvidenceId: EVIDENCE_ID,
    verifiedOutcome: status,
    verifiedAt: "2026-08-23T17:02:00.000Z",
    completedAt: "2026-08-23T17:02:00.000Z",
    ...overrides,
  };
}

function adapter(status = "completed", options = {}) {
  const calls = [];
  return {
    calls,
    async finalizeReview(input) {
      calls.push({ kind: "mutation", input });
      if (options.mutationError) throw new Error("post-commit uncertainty");
      return options.receipt || {
        dispatchId: DISPATCH_ID,
        planId: PLAN_ID,
        status,
        verificationEvidenceId: EVIDENCE_ID,
        idempotentReplay: options.idempotentReplay === true,
      };
    },
    async getExecution(input) {
      calls.push({ kind: "read", input });
      if (options.readError) throw new Error("read unavailable");
      return options.execution || terminal(status);
    },
  };
}

test("independent reviewer performs one finalization mutation and exact terminal readback", async () => {
  const { finalizeAttestedWorkerReview } = await subject();
  for (const [decision, status] of [["pass", "completed"], ["fail", "failed"]]) {
    const control = adapter(status);
    const result = await finalizeAttestedWorkerReview({
      request: reviewerRequest(decision),
      attestation: attestation(status),
      adapter: control,
    });
    assert.deepEqual(control.calls.map((call) => call.kind), ["mutation", "read"]);
    assert.deepEqual(control.calls[0].input, {
      organizationId: ORGANIZATION_ID,
      dispatchId: DISPATCH_ID,
      planId: PLAN_ID,
      verifierRuntimeProofId: PROOF_ID,
      verificationEvidenceId: EVIDENCE_ID,
      decision: status,
    });
    assert.equal(result.status, status);
    assert.equal(result.reconciledAfterUncertainMutation, false);
  }
});

test("exact terminal retry and post-commit uncertainty reconcile without a second mutation", async () => {
  const { finalizeAttestedWorkerReview } = await subject();
  const replay = adapter("completed", { idempotentReplay: true });
  const replayed = await finalizeAttestedWorkerReview({
    request: reviewerRequest(),
    attestation: attestation(),
    adapter: replay,
  });
  assert.equal(replayed.idempotentReplay, true);
  assert.deepEqual(replay.calls.map((call) => call.kind), ["mutation", "read"]);

  const uncertain = adapter("completed", { mutationError: true });
  const reconciled = await finalizeAttestedWorkerReview({
    request: reviewerRequest(),
    attestation: attestation(),
    adapter: uncertain,
  });
  assert.equal(reconciled.reconciledAfterUncertainMutation, true);
  assert.deepEqual(uncertain.calls.map((call) => call.kind), ["mutation", "read"]);
});

test("any plan, dispatch, proof, evidence, source, result, or terminal mismatch is ambiguous", async () => {
  const { finalizeAttestedWorkerReview } = await subject();
  for (const execution of [
    terminal("completed", { dispatchId: "661f0457-30af-4470-ad19-2d915e071716" }),
    terminal("completed", { evidenceSha256: "f".repeat(64) }),
    terminal("completed", { verifierRuntimeProofId: "661f0457-30af-4470-ad19-2d915e071716" }),
    terminal("completed", { args: { repository: "other/repo", exactSha: EXACT_SHA } }),
    terminal("completed", { resultSummary: {
      repository: "pandora-rvw-314296438-20260820/pandoras-box",
      exactSha: EXACT_SHA,
      sourceTreeSha: "f".repeat(40),
    } }),
  ]) {
    await assert.rejects(
      finalizeAttestedWorkerReview({
        request: reviewerRequest(),
        attestation: attestation(),
        adapter: adapter("completed", { execution }),
      }),
      /REVIEW_FINALIZATION_AMBIGUOUS/,
    );
  }
});

test("reviewer Edge owns finalization while the owner Edge has no finalization mutation", () => {
  const root = path.join(__dirname, "..");
  const reviewerEdge = fs.readFileSync(path.join(
    root,
    "supabase",
    "functions",
    "pandora-reviewer-attestation",
    "index.ts",
  ), "utf8");
  const ownerEdge = fs.readFileSync(path.join(
    root,
    "supabase",
    "functions",
    "pandora-owner-api",
    "index.ts",
  ), "utf8");

  assert.match(
    reviewerEdge,
    /record_governed_worker_review_attestation[\s\S]*finalizeAttestedWorkerReview[\s\S]*verify_governed_worker_dispatch[\s\S]*get_governed_worker_execution/,
  );
  assert.doesNotMatch(ownerEdge, /verify_governed_worker_dispatch/);
  assert.doesNotMatch(ownerEdge, /finalizeGovernedWorkerReview/);
  assert.doesNotMatch(ownerEdge, /finalize-review/);
});
