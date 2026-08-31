
"use strict";

const SHA256 = /^[0-9a-f]{64}$/;

function requiredText(value, label) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label} is required`);
  return value.trim();
}

function requiredDigest(value, label) {
  const normalized = requiredText(value, label).toLowerCase();
  if (!SHA256.test(normalized)) throw new Error(`${label} is invalid`);
  return normalized;
}

const RESTORE_SEMANTICS = Object.freeze({
  preview_switch: Object.freeze({
    key: "PREVIEW_SWITCH",
    intent_kind: "PREVIEW_VERSION",
    label: "Preview this version",
    summary: "Preview this version without changing the saved app, live app, or persistent data.",
    application_effect: "NONE",
    production_effect: "NONE",
    persistent_data_effect: "NONE",
    requires_confirmation: false,
    authority: "READ_ONLY_PREVIEW",
  }),
  application_restore: Object.freeze({
    key: "APPLICATION_RESTORE",
    intent_kind: "RESTORE_APPLICATION_VERSION",
    label: "Restore app version",
    summary: "Restore this earlier application version as project state. Persistent data is not reversed or recovered.",
    application_effect: "RESTORE_VERSION_STATE",
    production_effect: "NONE",
    persistent_data_effect: "UNCHANGED",
    requires_confirmation: true,
    authority: "PROJECT_VERSION_RESTORE",
  }),
  production_rollback: Object.freeze({
    key: "PRODUCTION_ROLLBACK",
    intent_kind: "ROLLBACK_PRODUCTION",
    label: "Roll back live app",
    summary: "Roll back the live application through the governed production rollback flow. Persistent data is unchanged.",
    application_effect: "NONE",
    production_effect: "ROLLBACK_LIVE_APPLICATION",
    persistent_data_effect: "UNCHANGED",
    requires_confirmation: true,
    authority: "GOVERNED_PRODUCTION_ROLLBACK",
  }),
  database_recovery: Object.freeze({
    key: "DATABASE_RECOVERY",
    intent_kind: "RECOVER_DATABASE",
    label: "Recover database",
    summary: "Recover persistent data from an explicit verified recovery point. This is separate from app-version restore and production rollback.",
    application_effect: "NONE",
    production_effect: "NONE",
    persistent_data_effect: "RECOVER_FROM_EXPLICIT_POINT",
    requires_confirmation: true,
    authority: "DATABASE_RECOVERY",
  }),
});

function getRestoreSemantics() {
  return RESTORE_SEMANTICS;
}

function createPreviewVersionIntent({ projectId, versionId, artifactDigestSha256 } = {}) {
  return Object.freeze({
    kind: RESTORE_SEMANTICS.preview_switch.intent_kind,
    project_id: requiredText(projectId, "project id"),
    version_id: requiredText(versionId, "version id"),
    artifact_digest_sha256: requiredDigest(artifactDigestSha256, "artifact digest sha256"),
    application_effect: "NONE",
    production_effect: "NONE",
    persistent_data_effect: "NONE",
    requires_confirmation: false,
  });
}

function createApplicationRestoreIntent({
  projectId,
  expectedVisibleCurrentVersionId,
  targetVersionId,
  expectedArtifactDigestSha256,
} = {}) {
  const visibleCurrent = requiredText(
    expectedVisibleCurrentVersionId,
    "expected visible current version id",
  );
  const target = requiredText(targetVersionId, "target version id");
  if (visibleCurrent === target) throw new Error("application restore target is already visible current");
  return Object.freeze({
    kind: RESTORE_SEMANTICS.application_restore.intent_kind,
    project_id: requiredText(projectId, "project id"),
    expected_visible_current_version_id: visibleCurrent,
    target_version_id: target,
    expected_artifact_digest_sha256: requiredDigest(
      expectedArtifactDigestSha256,
      "expected artifact digest sha256",
    ),
    application_effect: "RESTORE_VERSION_STATE",
    production_effect: "NONE",
    persistent_data_effect: "UNCHANGED",
    database_recovery_included: false,
    requires_confirmation: true,
    authority: "PROJECT_VERSION_RESTORE",
  });
}

function createProductionRollbackIntent({
  projectId,
  expectedProductionVersionId,
  targetVersionId,
} = {}) {
  const production = requiredText(expectedProductionVersionId, "expected production version id");
  const target = requiredText(targetVersionId, "target version id");
  if (production === target) throw new Error("production rollback target is already live");
  return Object.freeze({
    kind: RESTORE_SEMANTICS.production_rollback.intent_kind,
    project_id: requiredText(projectId, "project id"),
    expected_production_version_id: production,
    target_version_id: target,
    application_effect: "NONE",
    production_effect: "ROLLBACK_LIVE_APPLICATION",
    persistent_data_effect: "UNCHANGED",
    database_recovery_included: false,
    requires_confirmation: true,
    authority: "GOVERNED_PRODUCTION_ROLLBACK",
  });
}

function createDatabaseRecoveryIntent({
  projectId,
  recoveryPointId,
  recoveryPointSha256,
} = {}) {
  return Object.freeze({
    kind: RESTORE_SEMANTICS.database_recovery.intent_kind,
    project_id: requiredText(projectId, "project id"),
    recovery_point_id: requiredText(recoveryPointId, "recovery point id"),
    recovery_point_sha256: requiredDigest(recoveryPointSha256, "recovery point sha256"),
    application_effect: "NONE",
    production_effect: "NONE",
    persistent_data_effect: "RECOVER_FROM_EXPLICIT_POINT",
    application_restore_included: false,
    production_rollback_included: false,
    requires_confirmation: true,
    authority: "DATABASE_RECOVERY",
  });
}

module.exports = Object.freeze({
  getRestoreSemantics,
  createPreviewVersionIntent,
  createApplicationRestoreIntent,
  createProductionRollbackIntent,
  createDatabaseRecoveryIntent,
});
