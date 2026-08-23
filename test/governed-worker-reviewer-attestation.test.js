"use strict";

const assert = require("node:assert/strict");
const {
  generateKeyPairSync,
  sign,
  verify,
} = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.join(__dirname, "..");
const migration = fs.readFileSync(path.join(
  root,
  "supabase",
  "migrations",
  "20260823155000_add_governed_worker_reviewer_attestation.sql",
), "utf8");
const edge = fs.readFileSync(path.join(
  root,
  "supabase",
  "functions",
  "pandora-reviewer-attestation",
  "index.ts",
), "utf8");
const rollback = fs.readFileSync(path.join(
  root,
  "docs",
  "supabase",
  "recovery",
  "jcyqixttuebxqqfkjonq",
  "rollback",
  "20260823155000_disable_governed_worker_reviewer_attestation.sql",
), "utf8");

async function contract() {
  return import("../supabase/functions/pandora-reviewer-attestation/contract.mjs");
}

function request(signatureB64, now = new Date("2026-08-23T16:00:00.000Z")) {
  return {
    action: "attest",
    decision: "pass",
    dispatchId: "a6402a8a-4cbb-4812-80be-640028c81c5b",
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    nonce: "review-0123456789abcdef",
    organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
    planId: "8ec3acda-4fb7-48b2-81f4-6885c005f561",
    repository: "banataosystems/Pandoras-box",
    requestId: "661f0457-30af-4470-ad19-2d915e071716",
    reviewArtifactSha256: "a".repeat(64),
    reviewerId: "worker-reviewer-01",
    schemaVersion: 1,
    signatureB64,
    sourceTreeSha: "b".repeat(40),
    timestamp: now.toISOString(),
    verifierRuntimeProofId: "f17fcf24-35f6-49a8-b05c-2a6376666f51",
    workerEvidenceSha256: "c".repeat(64),
  };
}

test("reviewer request has a closed schema and one signature basis for every exact binding", async () => {
  const {
    reviewerAttestationSignatureBasis,
    validateReviewerAttestationRequest,
  } = await contract();
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const placeholder = Buffer.alloc(64, 7).toString("base64");
  const unsigned = request(placeholder);
  const basis = reviewerAttestationSignatureBasis(unsigned);
  const signatureB64 = sign(null, Buffer.from(basis), privateKey).toString("base64");
  const signed = request(signatureB64);

  assert.equal(
    validateReviewerAttestationRequest(
      signed,
      new Date("2026-08-23T16:00:00.000Z"),
    ),
    signed,
  );
  assert.equal(
    verify(null, Buffer.from(reviewerAttestationSignatureBasis(signed)), publicKey,
      Buffer.from(signatureB64, "base64")),
    true,
  );

  for (const [field, value] of [
    ["dispatchId", "b6402a8a-4cbb-4812-80be-640028c81c5b"],
    ["planId", "9ec3acda-4fb7-48b2-81f4-6885c005f561"],
    ["verifierRuntimeProofId", "e17fcf24-35f6-49a8-b05c-2a6376666f51"],
    ["workerEvidenceSha256", "d".repeat(64)],
    ["exactSha", "1".repeat(40)],
    ["sourceTreeSha", "2".repeat(40)],
    ["decision", "fail"],
    ["reviewArtifactSha256", "e".repeat(64)],
  ]) {
    assert.notEqual(
      reviewerAttestationSignatureBasis({ ...signed, [field]: value }),
      basis,
      `${field} was not signed`,
    );
  }
  assert.throws(
    () => validateReviewerAttestationRequest({ ...signed, ownerApproved: true }),
    /INVALID_REVIEWER_ATTESTATION/,
  );
  assert.throws(
    () => validateReviewerAttestationRequest({
      ...signed,
      organizationId: signed.organizationId.toUpperCase(),
    }),
    /INVALID_REVIEWER_ATTESTATION/,
  );
});

test("database authority keeps enrollment and attestation outside the owner service role", () => {
  assert.match(migration, /create role projectos_reviewer_ingest nologin noinherit/);
  assert.match(migration, /grant projectos_reviewer_ingest to authenticator/);
  assert.match(migration, /grant usage on schema public to projectos_reviewer_ingest/);
  assert.match(
    migration,
    /register_compute_reviewer_identity[\s\S]*database administrator required for reviewer enrollment/,
  );
  assert.match(
    migration,
    /revoke all on function public\.register_compute_reviewer_identity\([\s\S]*service_role, projectos_reviewer_ingest/,
  );
  assert.match(
    migration,
    /revoke all on function public\.record_governed_worker_review_attestation\([\s\S]*service_role;[\s\S]*grant execute on function public\.record_governed_worker_review_attestation\([\s\S]*to projectos_reviewer_ingest/,
  );
  assert.match(migration, /create table private\.reviewer_ingest_token_nonces/);
  assert.match(migration, /assert_reviewer_ingest_request/);
  assert.match(migration, /pandora-independent-review-authority/);
  assert.doesNotMatch(
    migration,
    /grant execute on function public\.record_governed_worker_review_attestation\([\s\S]*to service_role/,
  );
});

test("attestation is atomically nonce-protected, durable, exact, and required to finalize", () => {
  assert.match(migration, /reviewer_nonce_sha256 text not null/);
  assert.match(migration, /signed_timestamp text not null/);
  assert.match(migration, /signature_b64 text not null/);
  assert.match(migration, /signature_basis_sha256 text not null/);
  assert.match(
    migration,
    /signature_basis := concat_ws\([\s\S]*p_dispatch_id::text[\s\S]*p_plan_id::text[\s\S]*p_verifier_runtime_proof_id::text[\s\S]*p_worker_evidence_sha256[\s\S]*p_repository[\s\S]*p_exact_sha[\s\S]*p_source_tree_sha[\s\S]*p_decision[\s\S]*p_review_artifact_sha256/,
  );
  assert.match(
    migration,
    /dispatch\.status <> 'result_reported'[\s\S]*dispatch\.evidence_sha256 is distinct from p_worker_evidence_sha256[\s\S]*sourceTreeSha' is distinct from p_source_tree_sha/,
  );
  assert.match(
    migration,
    /plan\.args ->> 'repository' is distinct from p_repository[\s\S]*plan\.args ->> 'exactSha' is distinct from p_exact_sha/,
  );
  assert.match(
    migration,
    /agent_key <> dispatch\.worker_identity[\s\S]*verified_by <> dispatch\.worker_identity[\s\S]*verified_by <> agent_key/,
  );
  assert.match(
    migration,
    /insert into private\.compute_reviewer_nonces[\s\S]*on conflict do nothing[\s\S]*insert into public\.projectos_evidence[\s\S]*insert into private\.governed_worker_review_attestations/,
  );
  assert.match(
    migration,
    /guard_governed_worker_review_attestation[\s\S]*signed reviewer attestation required for finalization/,
  );
});

test("capability rollback disables actors but preserves signed evidence and the fail-closed guard", () => {
  assert.match(rollback, /set status = 'disabled'/);
  assert.match(rollback, /revoke execute[\s\S]*record_governed_worker_review_attestation/);
  assert.match(rollback, /Keep guard_governed_worker_review_attestation installed/);
  assert.doesNotMatch(rollback, /drop table|delete from|truncate|drop trigger/i);
});

test("Edge route verifies the enrolled key and uses only the reviewer-ingest role to mutate", () => {
  assert.match(edge, /functions-js@2\.4\.5/);
  assert.match(edge, /supabase-js@2\.57\.2/);
  assert.match(edge, /headers\.get\("authorization"\)/);
  assert.doesNotMatch(edge, /x-pandora-reviewer-authority/i);
  assert.match(edge, /pandora-independent-review-authority/);
  assert.match(edge, /purpose: "worker_review"/);
  assert.doesNotMatch(edge, /PANDORA_REVIEWER_INGEST_JWT|issue_reviewer_gateway_capability/);
  assert.match(edge, /claims\.role !== "projectos_reviewer_ingest"/);
  assert.match(edge, /SUPABASE_ANON_KEY[\s\S]*authorization: `Bearer \$\{validatedToken\}`/);
  assert.match(
    edge,
    /validateReviewerIngestJwt\(reviewerAuthorityToken,[\s\S]*consumeRateLimit[\s\S]*authenticateReviewer[\s\S]*reviewerIngestClient\([\s\S]*record_governed_worker_review_attestation/,
  );
  assert.match(edge, /REVIEWER_AUTHENTICATION_FAILED/);
  assert.match(edge, /consume_runtime_rate_limit/);
  assert.match(edge, /pandora-reviewer-attestation:v1:\$\{request\.reviewerId\}:attest/);
  assert.match(edge, /RATE_LIMITED[\s\S]*429/);
  assert.doesNotMatch(edge, /consume_compute_reviewer_nonce/);
  assert.match(edge, /p_nonce: request\.nonce/);
  assert.match(edge, /p_timestamp: request\.timestamp/);
  assert.match(edge, /p_signature_b64: request\.signatureB64/);
  assert.match(edge, /expectedSignatureBasisSha256/);
  assert.match(
    edge,
    /record_governed_worker_review_attestation[\s\S]*finalizeAttestedWorkerReview[\s\S]*verify_governed_worker_dispatch[\s\S]*get_governed_worker_execution/,
  );
  assert.match(edge, /MAX_BODY_BYTES = 32 \* 1024/);
  assert.match(edge, /request\.headers\.get\("origin"\)/);
  assert.doesNotMatch(edge, /auth\.getUser|getClaims\(/);
});
