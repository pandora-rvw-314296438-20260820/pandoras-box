"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const REQUEST_ID = "661f0457-30af-4470-ad19-2d915e071716";
const DISPATCH_ID = "a6402a8a-4cbb-4812-80be-640028c81c5b";
const PLAN_ID = "8ec3acda-4fb7-48b2-81f4-6885c005f561";
const WORKER_ID = "worker-01";
const SIGNATURE = Buffer.alloc(64, 7).toString("base64");

async function contract() {
  return import("../supabase/functions/pandora-worker-dispatch/contract.mjs");
}

function claim(now = new Date("2026-08-23T15:00:00.000Z")) {
  return {
    schemaVersion: 1,
    action: "claim",
    organizationId: ORGANIZATION_ID,
    workerId: WORKER_ID,
    requestId: REQUEST_ID,
    nonce: "nonce-0123456789abcdef",
    timestamp: now.toISOString(),
    signatureB64: SIGNATURE,
  };
}

function job() {
  return {
    schemaVersion: 1,
    audience: `pandora-worker:${WORKER_ID}`,
    organizationId: ORGANIZATION_ID,
    dispatchId: DISPATCH_ID,
    planId: PLAN_ID,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    jobClass: "node_regression",
    maxRuntimeSeconds: 1800,
    issuedAt: "2026-08-23T15:00:00.000Z",
    expiresAt: "2026-08-23T15:35:00.000Z",
    runnerPolicyHash: "a".repeat(64),
    runnerImageDigest: `sha256:${"b".repeat(64)}`,
    acquisitionImageDigest: `sha256:${"c".repeat(64)}`,
    networkPolicy: "none",
    isolation: "hyperv_container",
    productionMutationAllowed: false,
  };
}

function result(jobDigest) {
  return {
    schemaVersion: 1,
    organizationId: ORGANIZATION_ID,
    dispatchId: DISPATCH_ID,
    planId: PLAN_ID,
    workerId: WORKER_ID,
    jobDigest,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    jobClass: "node_regression",
    outcome: "completed",
    exitCode: 0,
    isolation: "hyperv_container",
    networkPolicy: "none",
    productionMutationAllowed: false,
    runnerPolicyHash: "a".repeat(64),
    runnerImageDigest: `sha256:${"b".repeat(64)}`,
    acquisitionImageDigest: `sha256:${"c".repeat(64)}`,
    sourceTreeSha: "d".repeat(40),
    testsDiscovered: 200,
    startedAt: "2026-08-23T15:01:00.000Z",
    completedAt: "2026-08-23T15:02:00.000Z",
    stdoutSha256: "e".repeat(64),
    stderrSha256: "f".repeat(64),
  };
}

test("claim request is closed-schema, current, and bound to a worker audience", async () => {
  const { claimSignatureBasis, validateClaimRequest } = await contract();
  const now = new Date("2026-08-23T15:00:00.000Z");
  assert.equal(validateClaimRequest(claim(now), now).workerId, WORKER_ID);
  assert.equal(
    claimSignatureBasis(claim(now)),
    `pandora-worker-request-v1|claim|${ORGANIZATION_ID}|${WORKER_ID}|${REQUEST_ID}|nonce-0123456789abcdef|2026-08-23T15:00:00.000Z`,
  );
  assert.throws(
    () => validateClaimRequest({ ...claim(now), command: "whoami" }, now),
    /INVALID_CLAIM_REQUEST/,
  );
  assert.throws(
    () => validateClaimRequest(claim(new Date("2026-08-23T14:40:00.000Z")), now),
    /INVALID_CLAIM_REQUEST/,
  );
});

test("job digest binds exact SHA, pinned images, no network, and no production mutation", async () => {
  const { jobDigest, validateJobPayload } = await contract();
  assert.equal(validateJobPayload(job()).audience, `pandora-worker:${WORKER_ID}`);
  assert.throws(
    () => validateJobPayload({ ...job(), repository: "banataosystems/Pandoras-box" }),
    /INVALID_JOB_PAYLOAD/,
  );
  const digest = await jobDigest(job());
  assert.match(digest, /^[0-9a-f]{64}$/);
  assert.throws(
    () => validateJobPayload({ ...job(), networkPolicy: "open" }),
    /INVALID_JOB_PAYLOAD/,
  );
  assert.throws(
    () => validateJobPayload({ ...job(), productionMutationAllowed: true }),
    /INVALID_JOB_PAYLOAD/,
  );
  assert.throws(
    () => validateJobPayload({ ...job(), shell: "powershell.exe" }),
    /INVALID_JOB_PAYLOAD/,
  );
});

test("completion evidence is exact, test-bearing, and hash-bound", async () => {
  const {
    completeSignatureBasis,
    jobDigest,
    resultEvidenceHash,
    validateCompleteRequest,
  } = await contract();
  const digest = await jobDigest(job());
  const summary = result(digest);
  const evidenceSha256 = await resultEvidenceHash(summary);
  const complete = {
    schemaVersion: 1,
    action: "complete",
    organizationId: ORGANIZATION_ID,
    workerId: WORKER_ID,
    requestId: REQUEST_ID,
    nonce: "complete-0123456789ab",
    timestamp: "2026-08-23T15:02:00.000Z",
    dispatchId: DISPATCH_ID,
    planId: PLAN_ID,
    outcome: "completed",
    durationMs: 60000,
    jobDigest: digest,
    evidenceSha256,
    resultSummary: summary,
    signatureB64: SIGNATURE,
  };
  assert.equal(
    validateCompleteRequest(complete, new Date("2026-08-23T15:02:00.000Z")).evidenceSha256,
    evidenceSha256,
  );
  assert.match(completeSignatureBasis(complete), new RegExp(`${evidenceSha256}$`));
  assert.throws(
    () => validateCompleteRequest({
      ...complete,
      resultSummary: { ...summary, testsDiscovered: 0 },
    }, new Date("2026-08-23T15:02:00.000Z")),
    /INVALID_RESULT_SUMMARY/,
  );
});

test("Edge gateway forwards one externally verified bearer and holds no mutation or signing secret", () => {
  const source = fs.readFileSync(
    path.join(
      __dirname,
      "..",
      "supabase",
      "functions",
      "pandora-worker-dispatch",
      "index.ts",
    ),
    "utf8",
  );
  assert.match(source, /function bearer\([\s\S]*headers\.get\("authorization"\)/);
  assert.match(source, /SUPABASE_ANON_KEY/);
  assert.match(source, /Authorization: `Bearer \$\{token\}`/);
  assert.match(source, /claim_governed_worker_dispatch_authorized/);
  assert.match(source, /record_governed_worker_job_envelope_authorized/);
  assert.match(source, /finish_governed_worker_dispatch_authorized/);
  assert.match(source, /externalJobSignature\([\s\S]*authorization: `Bearer \$\{authorityToken\}`/);
  assert.match(source, /PANDORA_WORKER_JOB_AUTHORITY_URL/);
  assert.doesNotMatch(source, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(source, /PANDORA_WORKER_CONTROL_PRIVATE_KEY|signControlDigest/);
  assert.doesNotMatch(source, /verifyWorkerSignature|consume_compute_worker_nonce/);
  assert.doesNotMatch(source, /upsert_agent_runtime_proof|refreshRuntimeProof/);
  assert.doesNotMatch(source, /console\.(?:log|info|error)/);
});
