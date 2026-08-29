"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");

const receipt = JSON.parse(readFileSync("docs/verification/WORKER_E_LIVE_PROOF_20260829.json", "utf8"));

test("Worker E live proof is authoritative PASS with historical failure preserved", () => {
  assert.equal(receipt.schema, "pandora.worker-e.live-proof/1");
  assert.equal(receipt.status, "PASS");
  assert.equal(receipt.publish_eligible, true);
  assert.equal(receipt.history.failing_version.verification, "FAIL");
  assert.equal(receipt.history.repaired_version.verification, "PASS");
  assert.equal(receipt.history.failing_version.acceptance_command_exit_code, 1);
  assert.equal(receipt.history.repaired_version.acceptance_command_exit_code, 0);
  assert.equal(receipt.history.repaired_version.lifecycle_status, "verified");
  assert.equal(
    receipt.history.repaired_version.authoritative_release_closure_verification_run_id,
    "e65a0e44-a9c6-44fe-8849-5c173ede24cb",
  );
  assert.deepEqual(receipt.remaining_required_proofs, []);
});

test("Worker E production proof is exact-source and exact-artifact bound", () => {
  assert.equal(receipt.provider_truth.exact_repaired_deployment, "PASS");
  assert.equal(receipt.provider_truth.preview.verification, "PASS");
  assert.equal(receipt.provider_truth.production.verification, "PASS");
  assert.equal(
    receipt.provider_truth.production.source_commit,
    receipt.history.repaired_version.source_commit,
  );
  assert.equal(
    receipt.provider_truth.production.artifact_sha256,
    receipt.history.repaired_version.artifact_sha256,
  );
  assert.equal(
    receipt.provider_truth.production.runtime_body_sha256,
    receipt.history.repaired_version.artifact_sha256,
  );
  assert.equal(receipt.provider_truth.production.runtime_http_status, 200);
  assert.equal(receipt.provider_truth.production.domain_verified, true);
  assert.equal(receipt.provider_truth.production.domain_misconfigured, false);
});

test("Worker E independently proves real Vercel rollback and restore", () => {
  const proof = receipt.provider_truth.rollback_restore;
  assert.equal(proof.verification, "PASS");
  assert.equal(proof.verification_run_id, "e65a0e44-a9c6-44fe-8849-5c173ede24cb");
  assert.equal(proof.preflight.verified_git_sources, true);
  assert.equal(proof.preflight.runtime_http_status, 200);
  assert.equal(proof.rollback.provider_http_status, 201);
  assert.equal(proof.rollback.runtime_http_status, 200);
  assert.equal(proof.restore.provider_http_status, 201);
  assert.equal(proof.restore.runtime_http_status, 200);
  assert.equal(proof.restore.restored_to_original, true);
  assert.equal(
    proof.rollback.runtime_body_sha256,
    proof.restore.runtime_body_sha256,
  );
});

test("Worker E live database proof is independently PASS with rollback complete", () => {
  assert.equal(receipt.database_proof.verification, "PASS");
  assert.equal(receipt.database_proof.rls_enabled, true);
  assert.ok(receipt.database_proof.constraint_count > 0);
  assert.ok(receipt.database_proof.index_count > 0);
  assert.ok(receipt.database_proof.policy_count > 0);
  assert.equal(receipt.database_proof.rollback_complete, true);
});

test("Worker E receipt contains only credential references, never raw credentials", () => {
  const raw = JSON.stringify(receipt);
  assert.equal(receipt.credential_handling.raw_credentials_committed, false);
  assert.equal(receipt.credential_handling.raw_credentials_in_evidence, false);
  assert.doesNotMatch(raw, /\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{20,}\b/);
  assert.doesNotMatch(raw, /\b(?:AIza|sk-|vc_)[A-Za-z0-9_-]{20,}\b/);
  assert.doesNotMatch(raw, /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/);
});
