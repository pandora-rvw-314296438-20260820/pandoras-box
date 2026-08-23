"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.join(__dirname, "..");
const migration = fs.readFileSync(path.join(
  root,
  "supabase",
  "migrations",
  "20260823171000_harden_owner_worker_external_authority.sql",
), "utf8");
const workerEdge = fs.readFileSync(path.join(
  root,
  "supabase",
  "functions",
  "pandora-worker-dispatch",
  "index.ts",
), "utf8");
const ownerEdge = fs.readFileSync(path.join(
  root,
  "supabase",
  "functions",
  "pandora-owner-api",
  "index.ts",
), "utf8");
const config = fs.readFileSync(path.join(root, "supabase", "config.toml"), "utf8");
const rollback = fs.readFileSync(path.join(
  root,
  "docs",
  "supabase",
  "recovery",
  "jcyqixttuebxqqfkjonq",
  "rollback",
  "20260823171000_restore_candidate_worker_gateway_authority.sql",
), "utf8");

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

test("ordinary worker-plan decisions bind a live owner session and never accept a supplied actor", () => {
  assert.match(migration, /auth\.sessions session[\s\S]*session\.id = current_session_id/);
  assert.match(migration, /session\.user_id = owner_user_id/);
  assert.match(migration, /session\.not_after is null or session\.not_after > statement_timestamp\(\)/);
  assert.match(migration, /jwt_aal not in \('aal1', 'aal2'\)/);
  assert.match(migration, /membership\.status = 'active'[\s\S]*membership\.role in \('owner', 'admin'\)/);
  assert.match(migration, /'owner:' \|\| owner_user_id::text/);
  assert.match(
    migration,
    /revoke all on function public\.decide_governed_worker_execution_plan\(uuid,uuid,text,text\)[\s\S]*service_role/,
  );
  const decideStart = ownerEdge.indexOf("async function decide(");
  const decideEnd = ownerEdge.indexOf("\nasync function", decideStart + 1);
  const decideSource = ownerEdge.slice(decideStart, decideEnd);
  assert.match(decideSource, /context\.client\.rpc/);
  assert.doesNotMatch(decideSource, /p_decided_by|SUPABASE_SERVICE_ROLE_KEY/);
});

test("claim and completion authority are exact, short-lived, one-shot, and unavailable to service_role", () => {
  assert.match(migration, /purpose in \('worker_claim', 'worker_complete'\)/);
  assert.match(migration, /authority_expires_at[\s\S]*primary key \(issuer, jti_sha256\)/);
  assert.match(migration, /token_exp > token_iat \+ interval '2 minutes'/);
  assert.match(migration, /on conflict do nothing[\s\S]*worker authority token already consumed/);
  assert.match(migration, /worker_claim_jti_sha256/);
  assert.match(migration, /worker_completion_signature_b64/);
  assert.match(migration, /bind_worker_completion_to_review/);
  assert.match(migration, /payload_redacted[\s\S]*'workerCompletion'/);
  for (const legacy of [
    "consume_compute_worker_nonce",
    "claim_governed_worker_dispatch",
    "record_governed_worker_job_envelope",
    "finish_governed_worker_dispatch",
  ]) {
    assert.match(
      migration,
      new RegExp(`revoke all on function public\\.${legacy}\\([\\s\\S]*?service_role`),
    );
  }
  assert.match(migration, /to projectos_worker_ingest/g);
  assert.doesNotMatch(migration, /grant execute[\s\S]{0,200}to service_role/);
});

test("claim authority digest matches the database domain separation", async () => {
  const { claimSignatureBasis, workerAuthorityRequestHash } = await import(
    "../supabase/functions/pandora-worker-dispatch/contract.mjs"
  );
  const signatureB64 = Buffer.alloc(64, 9).toString("base64");
  const request = {
    schemaVersion: 1,
    action: "claim",
    organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
    workerId: "worker-01",
    requestId: "661f0457-30af-4470-ad19-2d915e071716",
    nonce: "nonce-0123456789abcdef",
    timestamp: "2026-08-23T15:00:00.000Z",
    signatureB64,
  };
  const keyFingerprint = "a".repeat(64);
  const expected = sha256([
    "pandora-worker-authority-v1",
    "worker_claim",
    sha256(claimSignatureBasis(request)),
    keyFingerprint,
    sha256(Buffer.from(signatureB64, "base64")),
  ].join("|"));
  assert.equal(
    await workerAuthorityRequestHash("worker_claim", request, keyFingerprint),
    expected,
  );
});

test("worker and reviewer gateways require verified Authorization JWTs and forbid candidate issuer secrets", () => {
  for (const name of [
    "pandora-worker-dispatch",
    "pandora-reviewer-attestation",
    "pandora-release-review-attestation",
  ]) {
    assert.match(
      config,
      new RegExp(`\\[functions\\.${name}\\]\\s+verify_jwt = true`),
    );
  }
  assert.match(workerEdge, /headers\.get\("authorization"\)/);
  assert.match(workerEdge, /SUPABASE_ANON_KEY/);
  assert.match(workerEdge, /PANDORA_WORKER_JOB_AUTHORITY_URL/);
  assert.doesNotMatch(
    workerEdge,
    /SUPABASE_SERVICE_ROLE_KEY|PANDORA_WORKER_CONTROL_PRIVATE_KEY|signControlDigest/,
  );
});

test("worker rollback disables capability without deleting or restoring insecure authority", () => {
  assert.match(rollback, /FAIL-CLOSED CAPABILITY-DISABLE ROLLBACK/);
  assert.match(rollback, /decide_governed_worker_execution_plan\(\s*uuid,uuid,text\s*\)/);
  assert.match(rollback, /decide_governed_worker_execution_plan\(\s*uuid,uuid,text,text\s*\)/);
  for (const mutation of [
    "consume_compute_worker_nonce",
    "claim_governed_worker_dispatch",
    "record_governed_worker_job_envelope",
    "finish_governed_worker_dispatch",
    "claim_governed_worker_dispatch_authorized",
    "record_governed_worker_job_envelope_authorized",
    "finish_governed_worker_dispatch_authorized",
  ]) {
    assert.match(rollback, new RegExp(`revoke all on function public\\.${mutation}\\(`));
  }
  assert.match(rollback, /revoke projectos_worker_ingest from authenticator/);
  assert.match(rollback, /set status = 'draining'/);
  assert.match(
    rollback,
    /preserves the authority JTI[\s\S]*signed claim\/completion[\s\S]*reviewer\/physical/i,
  );
  assert.doesNotMatch(rollback, /\bgrant\s+(?:execute|usage|projectos_worker_ingest)\b/i);
  assert.doesNotMatch(rollback, /\bdrop\s+(?:table|column|trigger|function|role)\b/i);
  assert.doesNotMatch(rollback, /\b(?:delete\s+from|truncate)\b/i);
});
