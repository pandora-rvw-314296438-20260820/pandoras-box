
"use strict";

const SHA256 = /^[0-9a-f]{64}$/;
const MAX_HISTORY_VERSIONS = 500;

function requiredText(value, label) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label} is required`);
  return value.trim();
}

function optionalText(value, label) {
  if (value == null) return null;
  return requiredText(value, label);
}

function optionalDigest(value, label) {
  if (value == null) return null;
  const normalized = requiredText(value, label).toLowerCase();
  if (!SHA256.test(normalized)) throw new Error(`${label} is invalid`);
  return normalized;
}

function exactTimestamp(value, label) {
  const text = requiredText(value, label);
  if (!Number.isFinite(Date.parse(text))) throw new Error(`${label} is invalid`);
  return text;
}

function optionalTimestamp(value, label) {
  if (value == null) return null;
  return exactTimestamp(value, label);
}

function normalizeVersion(row) {
  if (!row || typeof row !== "object" || Array.isArray(row)) {
    throw new Error("project version must be an object");
  }
  const sequence = Number(row.sequence_no);
  if (!Number.isSafeInteger(sequence) || sequence < 1) {
    throw new Error("project version sequence number is invalid");
  }
  if (typeof row.rollback_eligible !== "boolean") {
    throw new Error("project version rollback eligibility is required");
  }
  return Object.freeze({
    id: requiredText(row.id, "project version id"),
    organization_id: requiredText(row.organization_id, "organization id"),
    project_id: requiredText(row.project_id, "project id"),
    sequence_no: sequence,
    kind: requiredText(row.kind, "project version kind"),
    parent_version_id: optionalText(row.parent_version_id, "parent version id"),
    artifact_digest_sha256: optionalDigest(
      row.artifact_digest_sha256,
      "project version artifact digest sha256",
    ),
    lifecycle_status: requiredText(row.lifecycle_status, "project version lifecycle status"),
    rollback_of_version_id: optionalText(row.rollback_of_version_id, "rollback source version id"),
    rollback_eligible: row.rollback_eligible,
    verification_run_id: optionalText(row.verification_run_id, "verification run id"),
    created_at: exactTimestamp(row.created_at, "project version created at"),
    promoted_at: optionalTimestamp(row.promoted_at, "project version promoted at"),
  });
}

function normalizeRoles(roles = {}) {
  if (!roles || typeof roles !== "object" || Array.isArray(roles)) {
    throw new Error("project version roles must be an object");
  }
  return Object.freeze({
    visible_current_version_id: optionalText(
      roles.visibleCurrentVersionId ?? roles.visible_current_version_id,
      "visible current version id",
    ),
    candidate_version_id: optionalText(
      roles.candidateVersionId ?? roles.candidate_version_id,
      "candidate version id",
    ),
    production_version_id: optionalText(
      roles.productionVersionId ?? roles.production_version_id,
      "production version id",
    ),
  });
}

function normalizeChangeSummaries(summaries, versionsById, organizationId, projectId) {
  if (!Array.isArray(summaries)) throw new Error("change summaries must be an array");
  const byCandidate = new Map();
  for (const summary of summaries) {
    if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
      throw new Error("human change summary must be an object");
    }
    if (summary.schema !== "pandora.human-change-summary/1" || summary.schema_version !== 1) {
      throw new Error("unsupported human change summary schema");
    }
    if (
      requiredText(summary.organization_id, "change summary organization id") !== organizationId ||
      requiredText(summary.project_id, "change summary project id") !== projectId
    ) {
      throw new Error("change summary belongs to a different project");
    }
    const currentId = requiredText(summary.current_version_id, "change summary current version id");
    const candidateId = requiredText(summary.candidate_version_id, "change summary candidate version id");
    if (byCandidate.has(candidateId)) {
      throw new Error(`duplicate change summary for version ${candidateId}`);
    }
    const candidate = versionsById.get(candidateId);
    if (!candidate) throw new Error(`change summary references unknown version ${candidateId}`);
    if (candidate.parent_version_id !== currentId) {
      throw new Error(`change summary lineage does not match version ${candidateId}`);
    }
    const current = versionsById.get(currentId);
    if (current && current.project_id !== candidate.project_id) {
      throw new Error("change summary lineage crosses projects");
    }
    const candidateDigest = optionalDigest(
      summary.candidate_artifact_digest_sha256,
      "change summary candidate artifact digest sha256",
    );
    if (
      candidate.artifact_digest_sha256 != null &&
      candidateDigest !== candidate.artifact_digest_sha256
    ) {
      throw new Error(`change summary artifact identity does not match version ${candidateId}`);
    }
    if (current) {
      const currentDigest = optionalDigest(
        summary.current_artifact_digest_sha256,
        "change summary current artifact digest sha256",
      );
      if (current.artifact_digest_sha256 != null && currentDigest !== current.artifact_digest_sha256) {
        throw new Error(`change summary artifact identity does not match version ${currentId}`);
      }
    }
    byCandidate.set(candidateId, Object.freeze({
      current_version_id: currentId,
      candidate_version_id: candidateId,
      headline: requiredText(summary.headline, "change summary headline"),
      material_change_count: Number.isSafeInteger(summary.material_change_count)
        ? summary.material_change_count
        : null,
    }));
  }
  return byCandidate;
}

function normalizeReceipts(receipts, versionsById) {
  if (!Array.isArray(receipts)) throw new Error("verification receipts must be an array");
  const byVersion = new Map();
  for (const receipt of receipts) {
    if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) {
      throw new Error("verification receipt must be an object");
    }
    if (
      receipt.schema !== "pandora.customer-verification-receipt/1" ||
      receipt.schema_version !== 1
    ) {
      throw new Error("unsupported verification receipt schema");
    }
    const versionId = requiredText(receipt.project_version_id, "verification receipt version id");
    if (!versionsById.has(versionId)) {
      throw new Error(`verification receipt references unknown version ${versionId}`);
    }
    if (byVersion.has(versionId)) {
      throw new Error(`duplicate verification receipt for version ${versionId}`);
    }
    byVersion.set(versionId, Object.freeze({
      verification_run_id: requiredText(receipt.verification_run_id, "verification run id"),
      state: requiredText(receipt.verification_state, "verification state"),
      headline: requiredText(receipt.headline, "verification headline"),
    }));
  }
  return byVersion;
}

function roleBadges(versionId, roles, rollbackOfVersionId) {
  const badges = [];
  if (versionId === roles.visible_current_version_id) badges.push("Current");
  if (versionId === roles.candidate_version_id && versionId !== roles.visible_current_version_id) {
    badges.push("Updating");
  }
  if (versionId === roles.production_version_id) badges.push("Live");
  if (rollbackOfVersionId != null) badges.push("Restored");
  return Object.freeze(badges);
}

function humanSummary(version, changeSummary) {
  if (changeSummary) return changeSummary.headline;
  if (version.rollback_of_version_id != null) return "Restored an earlier working version.";
  if (version.parent_version_id == null) return "Initial project version.";
  return "Saved project version.";
}

function actionsFor(version, roles, changeSummary) {
  const previewEnabled = version.artifact_digest_sha256 != null;
  const compareEnabled = changeSummary != null;
  const restoreEnabled =
    version.rollback_eligible === true &&
    version.artifact_digest_sha256 != null &&
    roles.visible_current_version_id != null &&
    version.id !== roles.visible_current_version_id &&
    version.id !== roles.candidate_version_id;

  return Object.freeze({
    preview: Object.freeze({
      enabled: previewEnabled,
      intent: previewEnabled
        ? Object.freeze({
          kind: "PREVIEW_VERSION",
          project_id: version.project_id,
          version_id: version.id,
          artifact_digest_sha256: version.artifact_digest_sha256,
          application_effect: "NONE",
          production_effect: "NONE",
          persistent_data_effect: "NONE",
          requires_confirmation: false,
        })
        : null,
    }),
    compare: Object.freeze({
      enabled: compareEnabled,
      intent: compareEnabled
        ? Object.freeze({
          kind: "COMPARE_VERSIONS",
          project_id: version.project_id,
          base_version_id: changeSummary.current_version_id,
          target_version_id: version.id,
        })
        : null,
    }),
    restore: Object.freeze({
      enabled: restoreEnabled,
      intent: restoreEnabled
        ? Object.freeze({
          kind: "RESTORE_APPLICATION_VERSION",
          project_id: version.project_id,
          expected_visible_current_version_id: roles.visible_current_version_id,
          target_version_id: version.id,
          expected_artifact_digest_sha256: version.artifact_digest_sha256,
          application_effect: "RESTORE_VERSION_STATE",
          production_effect: "NONE",
          persistent_data_effect: "UNCHANGED",
          database_recovery_included: false,
          requires_confirmation: true,
          authority: "PROJECT_VERSION_RESTORE",
        })
        : null,
    }),
  });
}

function createHumanVersionHistory({
  versions = [],
  roles = {},
  changeSummaries = [],
  verificationReceipts = [],
} = {}) {
  if (!Array.isArray(versions)) throw new Error("project versions must be an array");
  if (versions.length === 0) throw new Error("at least one project version is required");
  if (versions.length > MAX_HISTORY_VERSIONS) throw new Error("project version history exceeds limit");

  const normalizedRoles = normalizeRoles(roles);
  const normalizedVersions = versions.map(normalizeVersion);
  const first = normalizedVersions[0];
  const versionsById = new Map();
  const sequenceIds = new Set();
  for (const version of normalizedVersions) {
    if (version.organization_id !== first.organization_id || version.project_id !== first.project_id) {
      throw new Error("project version history crosses projects");
    }
    if (versionsById.has(version.id)) throw new Error(`duplicate project version id: ${version.id}`);
    if (sequenceIds.has(version.sequence_no)) {
      throw new Error(`duplicate project version sequence number: ${version.sequence_no}`);
    }
    versionsById.set(version.id, version);
    sequenceIds.add(version.sequence_no);
  }

  for (const version of normalizedVersions) {
    if (version.parent_version_id != null) {
      const parent = versionsById.get(version.parent_version_id);
      if (parent && parent.sequence_no >= version.sequence_no) {
        throw new Error(`project version lineage is not monotonic at ${version.id}`);
      }
    }
    if (version.rollback_of_version_id === version.id) {
      throw new Error(`project version cannot restore itself: ${version.id}`);
    }
  }

  const summariesByCandidate = normalizeChangeSummaries(
    changeSummaries,
    versionsById,
    first.organization_id,
    first.project_id,
  );
  const receiptsByVersion = normalizeReceipts(verificationReceipts, versionsById);

  const entries = [...normalizedVersions]
    .sort((a, b) => b.sequence_no - a.sequence_no)
    .map((version) => {
      const changeSummary = summariesByCandidate.get(version.id) ?? null;
      const receipt = receiptsByVersion.get(version.id) ?? null;
      const sourceRefs = [
        Object.freeze({
          kind: "project_version",
          id: version.id,
          sequence_no: version.sequence_no,
          artifact_digest_sha256: version.artifact_digest_sha256,
        }),
      ];
      if (changeSummary) {
        sourceRefs.push(Object.freeze({
          kind: "human_change_summary",
          current_version_id: changeSummary.current_version_id,
          candidate_version_id: changeSummary.candidate_version_id,
        }));
      }
      if (receipt) {
        sourceRefs.push(Object.freeze({
          kind: "verification_run",
          id: receipt.verification_run_id,
        }));
      }
      return Object.freeze({
        version_id: version.id,
        sequence_no: version.sequence_no,
        display_name: `Version ${version.sequence_no}`,
        created_at: version.created_at,
        promoted_at: version.promoted_at,
        lifecycle_status: version.lifecycle_status,
        role_badges: roleBadges(version.id, normalizedRoles, version.rollback_of_version_id),
        summary: humanSummary(version, changeSummary),
        verification: receipt
          ? Object.freeze({
            state: receipt.state,
            headline: receipt.headline,
            verification_run_id: receipt.verification_run_id,
          })
          : null,
        actions: actionsFor(version, normalizedRoles, changeSummary),
        source_refs: Object.freeze(sourceRefs),
      });
    });

  return Object.freeze({
    schema: "pandora.human-version-history/1",
    schema_version: 1,
    organization_id: first.organization_id,
    project_id: first.project_id,
    visible_current_version_id: normalizedRoles.visible_current_version_id,
    candidate_version_id: normalizedRoles.candidate_version_id,
    production_version_id: normalizedRoles.production_version_id,
    version_count: entries.length,
    versions: Object.freeze(entries),
  });
}

module.exports = { createHumanVersionHistory };
