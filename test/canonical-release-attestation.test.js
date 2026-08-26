"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const ORGANIZATION_ID = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const REQUEST_ID = "661f0457-30af-4470-ad19-2d915e071716";
const REVIEW_RECEIPT_ID = "77a2cf77-72b1-4bd1-9cd9-3e20ca6fa917";
const RUNTIME_PROOF_ID = "50be145d-87d8-4867-a27d-4f1515233e55";
const SOURCE_SHA = "0123456789abcdef0123456789abcdef01234567";
const SOURCE_TREE_SHA = "89abcdef0123456789abcdef0123456789abcdef";
const SIGNATURE = Buffer.alloc(64, 7).toString("base64");

function reviewRequest(now = new Date()) {
  return {
    schemaVersion: 1,
    action: "attest_canonical_release",
    organizationId: ORGANIZATION_ID,
    requestId: REQUEST_ID,
    reviewerId: "independent-reviewer-01",
    verifierRuntimeProofId: RUNTIME_PROOF_ID,
    nonce: "release-review-nonce-0001",
    timestamp: now.toISOString(),
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    sourceSha: SOURCE_SHA,
    sourceTreeSha: SOURCE_TREE_SHA,
    productionDeploymentId: "dpl_candidate123",
    rollbackDeploymentId: "dpl_rollback456",
    supabaseMigrationChainSha256: "a".repeat(64),
    reviewExternalId: "jules-release-review-001",
    reviewSourceUrl: "https://github.com/pandora-rvw-314296438-20260820/pandoras-box/issues/1",
    reviewDigest: "b".repeat(64),
    signatureB64: SIGNATURE,
  };
}

function ownerRequest(now = new Date()) {
  return {
    schemaVersion: 1,
    action: "authorize_canonical_release",
    organizationId: ORGANIZATION_ID,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    sourceSha: SOURCE_SHA,
    productionDeploymentId: "dpl_candidate123",
    reviewReceiptId: REVIEW_RECEIPT_ID,
    reviewReceiptSha256: "c".repeat(64),
    requestId: REQUEST_ID,
    authorizedAt: now.toISOString(),
  };
}

test("independent release review request is closed-schema and binds every release identity", async () => {
  const {
    releaseReviewSignatureBasis,
    validateReleaseReviewRequest,
  } = await import("../supabase/functions/pandora-release-review-attestation/contract.mjs");
  const now = new Date();
  const request = reviewRequest(now);
  assert.equal(validateReleaseReviewRequest(request, now).sourceSha, SOURCE_SHA);
  const basis = releaseReviewSignatureBasis(request);
  for (const binding of [
    SOURCE_SHA,
    SOURCE_TREE_SHA,
    "dpl_candidate123",
    "dpl_rollback456",
    "a".repeat(64),
    "b".repeat(64),
    "approved",
  ]) {
    assert.ok(basis.includes(binding));
  }
  assert.throws(
    () => validateReleaseReviewRequest({ ...request, selfApproved: true }, now),
    /INVALID_RELEASE_REVIEW_ATTESTATION/,
  );
  assert.throws(
    () => validateReleaseReviewRequest({
      ...request,
      rollbackDeploymentId: request.productionDeploymentId,
    }, now),
    /INVALID_RELEASE_REVIEW_ATTESTATION/,
  );
});

test("owner authorization request is closed-schema and exact-review bound", async () => {
  const { validateOwnerAuthorizationRequest } = await import(
    "../supabase/functions/pandora-release-owner-authorization/contract.mjs"
  );
  const now = new Date();
  const request = ownerRequest(now);
  assert.equal(
    validateOwnerAuthorizationRequest(request, now).reviewReceiptId,
    REVIEW_RECEIPT_ID,
  );
  assert.throws(
    () => validateOwnerAuthorizationRequest({ ...request, aal: "aal1" }, now),
    /INVALID_OWNER_AUTHORIZATION/,
  );
});

test("release reviewer Edge requires a one-shot external exact-request authority JWT", () => {
  const source = fs.readFileSync(path.join(
    __dirname,
    "..",
    "supabase",
    "functions",
    "pandora-release-review-attestation",
    "index.ts",
  ), "utf8");
  assert.match(source, /resolve_compute_reviewer_identity/);
  assert.match(source, /verifyReviewerSignature/);
  assert.match(source, /REVIEWER_AUTHENTICATION_FAILED/);
  assert.match(source, /claims\.role !== "projectos_reviewer_ingest"/);
  assert.match(source, /claims\.iss !== "pandora-independent-review-authority"/);
  assert.match(source, /claims\.pandora_request_sha256 !== expected\.requestSha256/);
  assert.match(source, /headers\.get\("authorization"\)/);
  assert.match(source, /authorization\.replace\(\/\^Bearer/);
  assert.doesNotMatch(source, /x-pandora-reviewer-authority/i);
  assert.match(source, /releaseReviewAuthorityBasis/);
  assert.doesNotMatch(source, /PANDORA_REVIEWER_INGEST_JWT|issue_reviewer_gateway_capability/);
  assert.match(
    source,
    /reviewerIngestClient\(reviewerAuthorityToken,[\s\S]*capture_canonical_release_review_receipt/,
  );
  assert.match(
    source,
    /validateReviewerIngestJwt\(reviewerAuthorityToken,[\s\S]*consumeAuthenticatedRateLimit[\s\S]*authenticateReviewer/,
  );
  assert.doesNotMatch(
    source,
    /rpc\(\s*client,\s*"capture_canonical_release_review_receipt"/,
  );
  assert.doesNotMatch(source, /consume_compute_reviewer_nonce/);
});

test("owner authorization Edge requires a live recently stepped-up AAL2 owner session", () => {
  const source = fs.readFileSync(path.join(
    __dirname,
    "..",
    "supabase",
    "functions",
    "pandora-release-owner-authorization",
    "index.ts",
  ), "utf8");
  assert.match(source, /client\.auth\.getUser\(\)/);
  assert.match(source, /claims\.aal !== "aal2"/);
  assert.match(source, /claims\.session_id/);
  assert.match(source, /claims\.amr/);
  assert.match(source, /RECENT_AAL2_SESSION_REQUIRED/);
  assert.match(source, /\.eq\("role", "owner"\)/);
  assert.match(source, /\.eq\("status", "active"\)/);
  assert.match(source, /owner\.client[\s\S]*capture_canonical_release_owner_authorization/);
});

test("release attestation migration is immutable, actor-separated, ordered, and status-projected", () => {
  const source = fs.readFileSync(path.join(
    __dirname,
    "..",
    "supabase",
    "migrations",
    "20260823160000_add_canonical_release_attestations.sql",
  ), "utf8");
  assert.match(source, /canonical_release_review_receipts_immutable/);
  assert.match(source, /canonical_release_owner_authorizations_immutable/);
  assert.match(source, /perform private\.assert_reviewer_ingest_role\(\)/);
  assert.match(source, /assert_reviewer_ingest_request/);
  assert.match(source, /grant execute[\s\S]*capture_canonical_release_review_receipt[\s\S]*to projectos_reviewer_ingest/);
  assert.match(source, /auth\.uid\(\) <> p_owner_user_id/);
  assert.match(source, /auth\.jwt\(\) ->> 'aal'[\s\S]*'aal2'/);
  assert.match(source, /from auth\.sessions session/);
  assert.match(source, /auth\.jwt\(\) -> 'amr'/);
  assert.match(source, /mfa_verified_at/);
  assert.match(source, /grant execute[\s\S]*capture_canonical_release_owner_authorization[\s\S]*to authenticated/);
  assert.match(source, /p_reviewed_at <= greatest\([\s\S]*rollback_restoration\.alias_post_observed_at[\s\S]*wifi\.observed_at[\s\S]*mobile_data\.observed_at/);
  assert.match(source, /insert into private\.compute_reviewer_nonces[\s\S]*on conflict do nothing/);
  assert.match(source, /p_authorized_at <= review_receipt\.captured_at/);
  assert.match(source, /'independentReview', review_status/);
  assert.match(source, /'ownerAuthorization', owner_status/);
  assert.doesNotMatch(source, /join public\.memberships membership/);
});

test("release attestation rollback disables capability and preserves gated evidence", () => {
  const rollback = fs.readFileSync(path.join(
    __dirname,
    "..",
    "docs",
    "supabase",
    "recovery",
    "jcyqixttuebxqqfkjonq",
    "rollback",
    "20260823160000_remove_canonical_release_attestations.sql",
  ), "utf8");
  assert.match(rollback, /FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK/);
  assert.match(rollback, /revoke all on function public\.capture_canonical_release_review_receipt/);
  assert.match(rollback, /revoke all on function public\.capture_canonical_release_owner_authorization/);
  assert.match(rollback, /revoke all on function public\.get_canonical_release_status\(uuid,text,text\)/);
  assert.match(rollback, /get_canonical_release_status_without_physical_android_authority/);
  assert.match(rollback, /revoke all on function public\.get_canonical_release_status_without_final_attestations/);
  assert.match(rollback, /begin;[\s\S]*commit;/);
  assert.doesNotMatch(
    rollback,
    /\b(?:drop|delete\s+from|truncate|grant\s+execute|rename\s+to)\b/i,
  );
});
