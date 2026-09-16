"use strict";

const assert = require("node:assert/strict");
const { pathToFileURL } = require("node:url");
const { join } = require("node:path");
const { test, before } = require("node:test");

let publisher;
const now = new Date("2026-09-16T07:00:00.000Z");
const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);

before(async () => {
  publisher = await import(pathToFileURL(join(
    __dirname, "..", "supabase/functions/pandora-coordinator-gate/publisher.mjs",
  )).href);
});

function envelope(overrides = {}) {
  return {
    schemaVersion: 1, repositoryId: 1345495177,
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    pullRequestNumber: 588, headSha: HEAD, baseRef: "main", baseSha: BASE,
    rulesetId: 21532267, ruleContext: "Pandora coordinator / integration",
    integrationAppId: 4785021,
    spreadsheetId: "1nTpPa1IQgbKsStpEcMnkIXiz3nDcgZjm02rZXPrXXk0",
    authoritativeSnapshotGeneration: 3,
    authoritativeSnapshotRevision: "execution-plan-row-199",
    authoritativeSnapshotSha256: "c".repeat(64),
    criticalHighHoldDispositions: [{
      id: "R-058", severity: "HIGH", scope: "MERGE",
      status: "HOLD", evidenceRef: "evidence-row-199",
    }],
    policyVersion: "D-041", decisionGeneration: 1,
    priorGeneration: null, priorCheckRunId: null,
    decision: "HOLD", reasons: ["Trusted publisher closure is still pending."],
    reviewId: "kimi-review-r058", reviewerVendor: "kimi-k3",
    reviewCandidateSha: HEAD, decisionNonce: "nonce-generation-0001",
    evaluatedAt: "2026-09-16T07:00:00.000Z",
    expiresAt: "2026-09-16T07:10:00.000Z",
    ...overrides,
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}
function providerFixture() {
  let nextId = 9001;
  const state = { checks: [], writes: [], ambiguousCreate: false, ambiguousUpdate: false };
  const decorate = (body, id) => ({
    id,
    ...clone(body),
    app: { id: 4785021, slug: "pandora" },
    head_sha: body.head_sha || HEAD,
  });
  const provider = {
    state,
    async getPull(number) {
      return { number, state: "open", merged: false, head: { sha: HEAD }, base: { ref: "main", sha: BASE } };
    },
    async getMainSha() { return BASE; },
    async listChecks(headSha) { return clone(state.checks.filter((row) => row.head_sha === headSha)); },
    async getCheck(id) { return clone(state.checks.find((row) => row.id === id)); },
    async createCheck(body) {
      const row = decorate(body, nextId++);
      state.checks.push(row); state.writes.push({ kind: "create", body: clone(body) });
      if (state.ambiguousCreate) { state.ambiguousCreate = false; throw new Error("GITHUB_WRITE_AMBIGUOUS"); }
      return clone(row);
    },
    async updateCheck(id, body) {
      const index = state.checks.findIndex((row) => row.id === id);
      if (index < 0) throw new Error("CHECK_NOT_FOUND");
      state.checks[index] = decorate({ ...state.checks[index], ...clone(body) }, id);
      state.writes.push({ kind: "update", id, body: clone(body) });
      if (state.ambiguousUpdate) { state.ambiguousUpdate = false; throw new Error("GITHUB_WRITE_AMBIGUOUS"); }
      return clone(state.checks[index]);
    },
  };
  return provider;
}

test("HOLD creates one App-bound non-success check and replays idempotently", async () => {
  const provider = providerFixture();
  const first = await publisher.publishDecision(provider, envelope(), now);
  assert.equal(first.state, "created");
  assert.equal(first.check.app.id, 4785021);
  assert.equal(first.check.conclusion, "action_required");
  assert.equal(provider.state.writes.length, 1);
  const replay = await publisher.publishDecision(provider, envelope(), now);
  assert.equal(replay.state, "idempotent");
  assert.equal(provider.state.writes.length, 1);
});
test("new PASS generation transitions through in-progress before success", async () => {
  const provider = providerFixture();
  const hold = await publisher.publishDecision(provider, envelope(), now);
  const passEnvelope = envelope({
    decisionGeneration: 2,
    priorGeneration: 1,
    priorCheckRunId: hold.check.id,
    decision: "PASS",
    reasons: ["All applicable merge holds are independently cleared."],
    criticalHighHoldDispositions: [],
    decisionNonce: "nonce-generation-0002",
  });
  const result = await publisher.publishDecision(provider, passEnvelope, now);
  assert.equal(result.state, "updated");
  assert.equal(result.check.conclusion, "success");
  assert.equal(provider.state.writes.length, 3);
  assert.equal(provider.state.writes[1].body.status, "in_progress");
  assert.equal(provider.state.writes[2].body.conclusion, "success");
});

test("same generation cannot change envelope or resurrect a completed decision", async () => {
  const provider = providerFixture();
  await publisher.publishDecision(provider, envelope(), now);
  await assert.rejects(
    publisher.publishDecision(provider, envelope({ reasons: ["Different same-generation reason."] }), now),
    /SAME_GENERATION_CONFLICT/,
  );
});
test("ambiguous create is reconciled by provider readback instead of duplicated", async () => {
  const provider = providerFixture();
  provider.state.ambiguousCreate = true;
  const result = await publisher.publishDecision(provider, envelope(), now);
  assert.equal(result.state, "created");
  assert.equal(provider.state.checks.length, 1);
  assert.equal(provider.state.writes.length, 1);
});

test("duplicate trusted App checks fail closed", async () => {
  const provider = providerFixture();
  const created = await publisher.publishDecision(provider, envelope(), now);
  provider.state.checks.push({ ...clone(created.check), id: created.check.id + 1 });
  await assert.rejects(
    publisher.publishDecision(provider, envelope(), now),
    /DUPLICATE_TRUSTED_CHECKS/,
  );
});

test("head/base/main drift is rejected before a check write", async () => {
  const provider = providerFixture();
  provider.getMainSha = async () => "d".repeat(40);
  await assert.rejects(publisher.publishDecision(provider, envelope(), now), /LIVE_IDENTITY_MISMATCH/);
  assert.equal(provider.state.writes.length, 0);
});
test("expired successful decisions are actively invalidated", async () => {
  const provider = providerFixture();
  const pass = envelope({
    decision: "PASS",
    reasons: ["All applicable merge holds are independently cleared."],
    criticalHighHoldDispositions: [],
  });
  const created = await publisher.publishDecision(provider, pass, now);
  assert.equal(created.check.conclusion, "success");
  const result = await publisher.expireCheck(
    provider,
    created.check.id,
    HEAD,
    new Date("2026-09-16T07:10:01.000Z"),
  );
  assert.equal(result.state, "expired");
  assert.equal(result.check.conclusion, "action_required");
});

test("wrong-App same-name checks never satisfy trusted publisher state", async () => {
  const provider = providerFixture();
  provider.state.checks.push({
    id: 44, name: "Pandora coordinator / integration", head_sha: HEAD,
    status: "completed", conclusion: "success", external_id: "spoof", app: { id: 15368 },
  });
  const result = await publisher.publishDecision(provider, envelope(), now);
  assert.equal(result.state, "created");
  assert.equal(result.check.app.id, 4785021);
});

test("snapshot promotion revokes a prior PASS with provider readback and idempotent retry", async () => {
  const provider = providerFixture();
  const pass = envelope({
    decision: "PASS",
    reasons: ["All applicable merge holds are independently cleared."],
    criticalHighHoldDispositions: [],
  });
  const created = await publisher.publishDecision(provider, pass, now);
  provider.state.ambiguousUpdate = true;
  const revoked = await publisher.revokeCheckForSnapshot(
    provider, created.check.id, HEAD, "promotion-0001", new Date("2026-09-16T07:01:00.000Z"),
  );
  assert.equal(revoked.state, "revoked");
  assert.equal(revoked.check.conclusion, "action_required");
  const writesAfterRevoke = provider.state.writes.length;
  const replay = await publisher.revokeCheckForSnapshot(
    provider, created.check.id, HEAD, "promotion-0001", new Date("2026-09-16T07:01:01.000Z"),
  );
  assert.equal(replay.state, "already_invalid");
  assert.equal(provider.state.writes.length, writesAfterRevoke);
});