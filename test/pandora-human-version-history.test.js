
"use strict";
const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");
const { createHumanVersionHistory } = verification;
const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const D = (ch) => ch.repeat(64);

function version(sequence, overrides = {}) {
  return {
    id: U(sequence),
    organization_id: U(10),
    project_id: U(11),
    sequence_no: sequence,
    kind: "build",
    parent_version_id: sequence === 1 ? null : U(sequence - 1),
    artifact_digest_sha256: D(String(sequence)),
    lifecycle_status: "ready",
    rollback_of_version_id: null,
    rollback_eligible: sequence < 3,
    verification_run_id: null,
    created_at: `2026-09-01T0${sequence}:00:00Z`,
    promoted_at: null,
    source_payload: { model_claim: "revenue doubled" },
    source_commit: "deadbeef",
    raw_diff: "@@",
    ...overrides,
  };
}

function summary(current, candidate, headline) {
  return {
    schema: "pandora.human-change-summary/1",
    schema_version: 1,
    organization_id: U(10),
    project_id: U(11),
    current_version_id: current.id,
    candidate_version_id: candidate.id,
    current_artifact_digest_sha256: current.artifact_digest_sha256,
    candidate_artifact_digest_sha256: candidate.artifact_digest_sha256,
    headline,
    material_change_count: 2,
  };
}

function receipt(v, state = "PASS") {
  return {
    schema: "pandora.customer-verification-receipt/1",
    schema_version: 1,
    verification_run_id: U(100 + v.sequence_no),
    project_version_id: v.id,
    verification_state: state,
    headline: state === "PASS" ? "Verified" : "Verification in progress",
  };
}

test("history composes exact versions, summaries, receipts, and bounded actions", () => {
  const v1 = version(1);
  const v2 = version(2, { promoted_at: "2026-09-01T02:30:00Z" });
  const v3 = version(3, { rollback_eligible: false });
  const history = createHumanVersionHistory({
    versions: [v1, v2, v3],
    roles: {
      visibleCurrentVersionId: v2.id,
      candidateVersionId: v3.id,
      productionVersionId: v2.id,
    },
    changeSummaries: [
      summary(v1, v2, "Updated main experience."),
      summary(v2, v3, "Updated visual styling."),
    ],
    verificationReceipts: [receipt(v2), receipt(v3, "RUNNING")],
  });

  assert.equal(history.schema, "pandora.human-version-history/1");
  assert.deepEqual(history.versions.map((item) => item.sequence_no), [3, 2, 1]);
  assert.deepEqual(history.versions[0].role_badges, ["Updating"]);
  assert.deepEqual(history.versions[1].role_badges, ["Current", "Live"]);
  assert.equal(history.versions[0].summary, "Updated visual styling.");
  assert.equal(history.versions[1].verification.state, "PASS");
  assert.equal(history.versions[0].actions.compare.enabled, true);
  assert.equal(history.versions[0].actions.restore.enabled, false);
  assert.equal(history.versions[2].actions.restore.enabled, true);
  assert.deepEqual(history.versions[2].actions.restore.intent, {
    kind: "RESTORE_VERSION",
    project_id: U(11),
    expected_visible_current_version_id: v2.id,
    target_version_id: v1.id,
    expected_artifact_digest_sha256: v1.artifact_digest_sha256,
    requires_confirmation: true,
  });

  const serialized = JSON.stringify(history);
  assert.equal(serialized.includes("revenue doubled"), false);
  assert.equal(serialized.includes("deadbeef"), false);
  assert.equal(serialized.includes("@@"), false);
  assert.equal(serialized.toLowerCase().includes("git"), false);
});

test("history keeps restore as an exact stale-protected intent", () => {
  const v1 = version(1);
  const v2 = version(2, { rollback_eligible: true });
  const input = [v1, v2];
  const history = createHumanVersionHistory({
    versions: input,
    roles: { visibleCurrentVersionId: v2.id },
  });

  assert.equal(history.versions[0].actions.restore.enabled, false);
  assert.equal(history.versions[1].actions.restore.enabled, true);
  assert.equal(
    history.versions[1].actions.restore.intent.expected_visible_current_version_id,
    v2.id,
  );
  assert.equal(history.versions[1].actions.restore.intent.target_version_id, v1.id);
  assert.equal(input[0].lifecycle_status, "ready");
});

test("history fails closed on project, sequence, digest, and summary-lineage ambiguity", () => {
  const v1 = version(1);
  const v2 = version(2);

  assert.throws(
    () => createHumanVersionHistory({ versions: [v1, { ...v2, project_id: U(12) }] }),
    /crosses projects/,
  );
  assert.throws(
    () => createHumanVersionHistory({ versions: [v1, { ...v2, sequence_no: 1 }] }),
    /duplicate project version sequence/,
  );
  assert.throws(
    () => createHumanVersionHistory({ versions: [{ ...v1, artifact_digest_sha256: "bad" }] }),
    /artifact digest sha256 is invalid/,
  );
  const badSummary = summary(v1, v2, "Updated main experience.");
  badSummary.current_version_id = U(99);
  assert.throws(
    () => createHumanVersionHistory({ versions: [v1, v2], changeSummaries: [badSummary] }),
    /lineage does not match/,
  );
});

test("missing exact artifact disables preview and restore rather than guessing", () => {
  const v1 = version(1, { artifact_digest_sha256: null, rollback_eligible: true });
  const history = createHumanVersionHistory({
    versions: [v1],
    roles: { visibleCurrentVersionId: U(99) },
  });
  assert.equal(history.versions[0].actions.preview.enabled, false);
  assert.equal(history.versions[0].actions.restore.enabled, false);
});

test("rollback lineage receives a human restored label without raw source details", () => {
  const v1 = version(1);
  const v2 = version(2, { rollback_of_version_id: v1.id });
  const history = createHumanVersionHistory({
    versions: [v1, v2],
    roles: { visibleCurrentVersionId: v2.id, productionVersionId: v2.id },
  });
  assert.equal(history.versions[0].summary, "Restored an earlier working version.");
  assert.deepEqual(history.versions[0].role_badges, ["Current", "Live", "Restored"]);
});
