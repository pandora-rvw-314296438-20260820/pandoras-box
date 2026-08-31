
"use strict";
const assert = require("node:assert/strict");
const { test } = require("node:test");
const verification = require("../packages/pandora-verification/src");

const D = (ch) => ch.repeat(64);
const U = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

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
    rollback_eligible: true,
    verification_run_id: null,
    created_at: `2026-09-01T0${sequence}:00:00Z`,
    promoted_at: null,
    ...overrides,
  };
}

test("four restore meanings are explicit and non-overlapping", () => {
  const contract = verification.getRestoreSemantics();
  assert.deepEqual(Object.keys(contract), [
    "preview_switch",
    "application_restore",
    "production_rollback",
    "database_recovery",
  ]);
  assert.equal(new Set(Object.values(contract).map((item) => item.intent_kind)).size, 4);
  assert.equal(contract.preview_switch.persistent_data_effect, "NONE");
  assert.equal(contract.application_restore.persistent_data_effect, "UNCHANGED");
  assert.equal(contract.production_rollback.persistent_data_effect, "UNCHANGED");
  assert.equal(contract.database_recovery.persistent_data_effect, "RECOVER_FROM_EXPLICIT_POINT");
});

test("application restore is stale protected and explicitly excludes database recovery", () => {
  const intent = verification.createApplicationRestoreIntent({
    projectId: "project-1",
    expectedVisibleCurrentVersionId: "version-3",
    targetVersionId: "version-1",
    expectedArtifactDigestSha256: D("a"),
  });
  assert.equal(intent.kind, "RESTORE_APPLICATION_VERSION");
  assert.equal(intent.persistent_data_effect, "UNCHANGED");
  assert.equal(intent.database_recovery_included, false);
  assert.equal(intent.authority, "PROJECT_VERSION_RESTORE");
  assert.equal(intent.requires_confirmation, true);
  assert.throws(
    () => verification.createApplicationRestoreIntent({
      projectId: "project-1",
      expectedVisibleCurrentVersionId: "version-1",
      targetVersionId: "version-1",
      expectedArtifactDigestSha256: D("a"),
    }),
    /already visible current/,
  );
});

test("production rollback stays under governed production authority and leaves data unchanged", () => {
  const intent = verification.createProductionRollbackIntent({
    projectId: "project-1",
    expectedProductionVersionId: "version-3",
    targetVersionId: "version-2",
  });
  assert.equal(intent.kind, "ROLLBACK_PRODUCTION");
  assert.equal(intent.authority, "GOVERNED_PRODUCTION_ROLLBACK");
  assert.equal(intent.persistent_data_effect, "UNCHANGED");
  assert.equal(intent.database_recovery_included, false);
});

test("database recovery requires an exact recovery point and remains independent", () => {
  const intent = verification.createDatabaseRecoveryIntent({
    projectId: "project-1",
    recoveryPointId: "backup-2026-09-01",
    recoveryPointSha256: D("b"),
  });
  assert.equal(intent.kind, "RECOVER_DATABASE");
  assert.equal(intent.authority, "DATABASE_RECOVERY");
  assert.equal(intent.persistent_data_effect, "RECOVER_FROM_EXPLICIT_POINT");
  assert.equal(intent.application_restore_included, false);
  assert.equal(intent.production_rollback_included, false);
  assert.throws(
    () => verification.createDatabaseRecoveryIntent({
      projectId: "project-1",
      recoveryPointId: "backup-2026-09-01",
      recoveryPointSha256: "bad",
    }),
    /recovery point sha256 is invalid/,
  );
});

test("human version history exposes preview and application restore data effects explicitly", () => {
  const v1 = version(1);
  const v2 = version(2);
  const history = verification.createHumanVersionHistory({
    versions: [v1, v2],
    roles: { visibleCurrentVersionId: v2.id, productionVersionId: v2.id },
  });
  assert.equal(history.versions[0].actions.preview.intent.persistent_data_effect, "NONE");
  const restore = history.versions[1].actions.restore.intent;
  assert.equal(restore.kind, "RESTORE_APPLICATION_VERSION");
  assert.equal(restore.persistent_data_effect, "UNCHANGED");
  assert.equal(restore.database_recovery_included, false);
});

test("customer language never claims application restore reverses persistent data", () => {
  const contract = verification.getRestoreSemantics();
  assert.match(
    contract.application_restore.summary,
    /Persistent data is not reversed or recovered/,
  );
  assert.match(contract.production_rollback.summary, /Persistent data is unchanged/);
  assert.doesNotMatch(contract.preview_switch.summary, /recover database/i);
});
