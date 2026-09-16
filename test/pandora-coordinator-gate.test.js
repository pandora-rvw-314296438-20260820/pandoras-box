"use strict";

const assert = require("node:assert/strict");
const { pathToFileURL } = require("node:url");
const { join } = require("node:path");
const { test, before } = require("node:test");

let contract;
const now = new Date("2026-09-16T07:00:00.000Z");

before(async () => {
  contract = await import(pathToFileURL(join(
    __dirname,
    "..",
    "supabase/functions/pandora-coordinator-gate/contract.mjs",
  )).href);
});

function envelope(overrides = {}) {
  return {
    schemaVersion: 1,
    repositoryId: 1345495177,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    pullRequestNumber: 588,
    headSha: "a".repeat(40),
    baseRef: "main",
    baseSha: "b".repeat(40),
    rulesetId: 21532267,
    ruleContext: "Pandora coordinator / integration",
    integrationAppId: 4785021,
    spreadsheetId: "1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0",
    authoritativeSnapshotGeneration: 3,
    authoritativeSnapshotRevision: "execution-plan-row-199",
    authoritativeSnapshotSha256: "c".repeat(64),
    criticalHighHoldDispositions: [{
      id: "R-058",
      severity: "HIGH",
      scope: "MERGE",
      status: "HOLD",
      evidenceRef: "evidence-row-199",
    }],
    policyVersion: "D-041",
    decisionGeneration: 7,
    priorGeneration: 6,
    priorCheckRunId: 123456,
    decision: "HOLD",
    reasons: ["Trusted publisher closure is still pending."],
    reviewId: "kimi-review-6aa97f6efad06c111d049f17",
    reviewerVendor: "kimi-k3",
    reviewCandidateSha: "a".repeat(40),
    decisionNonce: "nonce-20260916-generation-7",
    evaluatedAt: "2026-09-16T07:00:00.000Z",
    expiresAt: "2026-09-16T07:10:00.000Z",
    ...overrides,
  };
}

test("R-058 envelope freezes exact repository, PR, head, base, ruleset, App, and Sheet identity", () => {
  assert.equal(contract.validateEnvelope(envelope(), now).decision, "HOLD");
  for (const patch of [
    { repository: "evil/repo" },
    { headSha: "not-a-sha" },
    { baseSha: "not-a-sha" },
    { rulesetId: 1 },
    { integrationAppId: 15368 },
    { spreadsheetId: "wrong" },
  ]) {
    assert.throws(() => contract.validateEnvelope(envelope(patch), now), /INVALID_COORDINATOR_ENVELOPE/);
  }
});
test("PASS fails closed on applicable Critical/High HOLD or UNKNOWN dispositions", () => {
  for (const status of ["HOLD", "UNKNOWN"]) {
    assert.throws(() => contract.validateEnvelope(envelope({
      decision: "PASS",
      criticalHighHoldDispositions: [{
        id: "R-058",
        severity: "HIGH",
        scope: "MERGE",
        status,
        evidenceRef: "evidence-row-199",
      }],
    }), now), /INVALID_COORDINATOR_ENVELOPE/);
  }
  const pass = envelope({
    decision: "PASS",
    reasons: ["All applicable merge holds are independently cleared."],
    criticalHighHoldDispositions: [{
      id: "R-058", severity: "HIGH", scope: "MERGE",
      status: "CLEARED", evidenceRef: "independent-review-r058",
    }],
  });
  assert.equal(contract.validateEnvelope(pass, now).decision, "PASS");
});
test("freshness, expiry, generation, and prior-check monotonicity fail closed", () => {
  for (const patch of [
    { evaluatedAt: "2026-09-16T06:54:59.000Z" },
    { expiresAt: "2026-09-16T07:00:00.000Z" },
    { expiresAt: "2026-09-16T07:16:00.000Z" },
    { decisionGeneration: 7, priorGeneration: 7 },
    { decisionGeneration: 6, priorGeneration: 7 },
    { priorCheckRunId: 0 },
  ]) {
    assert.throws(() => contract.validateEnvelope(envelope(patch), now), /INVALID_COORDINATOR_ENVELOPE/);
  }
});

test("canonical binding is deterministic and changes for ABA-relevant inputs", async () => {
  const first = await contract.bindEnvelope(envelope(), now);
  const replay = await contract.bindEnvelope(envelope(), now);
  const nextGeneration = await contract.bindEnvelope(envelope({
    decisionGeneration: 8,
    priorGeneration: 7,
    decisionNonce: "nonce-20260916-generation-8",
  }), now);
  assert.equal(first.envelopeHash, replay.envelopeHash);
  assert.equal(first.idempotencyKey, replay.idempotencyKey);
  assert.notEqual(first.envelopeHash, nextGeneration.envelopeHash);
  assert.notEqual(first.idempotencyKey, nextGeneration.idempotencyKey);
});
test("check metadata round-trips generation, expiry, envelope hash, and idempotency", async () => {
  const binding = await contract.bindEnvelope(envelope(), now);
  const desired = contract.desiredCheckState(binding);
  const parsed = contract.parseCheckExternalId(desired.external_id);
  assert.deepEqual(parsed, {
    generation: 7,
    envelopeHash: binding.envelopeHash,
    idempotencyKey: binding.idempotencyKey,
    expiresAt: "2026-09-16T07:10:00.000Z",
  });
  assert.equal(desired.name, "Pandora coordinator / integration");
  assert.equal(desired.head_sha, "a".repeat(40));
  assert.equal(desired.status, "completed");
  assert.equal(desired.conclusion, "action_required");
});

test("PASS is represented only as completed success", async () => {
  const binding = await contract.bindEnvelope(envelope({
    decision: "PASS",
    reasons: ["All applicable merge holds are independently cleared."],
    criticalHighHoldDispositions: [],
  }), now);
  const desired = contract.desiredCheckState(binding);
  assert.equal(desired.status, "completed");
  assert.equal(desired.conclusion, "success");
});
