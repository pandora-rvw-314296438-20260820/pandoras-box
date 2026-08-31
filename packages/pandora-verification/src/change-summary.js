
"use strict";

const SHA256 = /^[0-9a-f]{64}$/;
const MAX_MANIFEST_FILES = 1000;

function requiredText(value, label) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${label} is required`);
  return value.trim();
}

function exactDigest(value, label) {
  const normalized = requiredText(value, label).toLowerCase();
  if (!SHA256.test(normalized)) throw new Error(`${label} is invalid`);
  return normalized;
}

function safePath(value, label) {
  const path = requiredText(value, label);
  if (
    path.length > 512 ||
    path.startsWith("/") ||
    path.endsWith("/") ||
    path.includes("\\") ||
    path.includes("\0") ||
    path.includes("?") ||
    path.includes("#") ||
    path.split("/").some((part) => !part || part === "." || part === ".." || part.length > 255)
  ) {
    throw new Error(`${label} is invalid`);
  }
  return path;
}

function normalizeVersion(version, role) {
  if (!version || typeof version !== "object" || Array.isArray(version)) {
    throw new Error(`${role} project version is required`);
  }
  return Object.freeze({
    id: requiredText(version.id, `${role} project version id`),
    organization_id: requiredText(version.organization_id, `${role} organization id`),
    project_id: requiredText(version.project_id, `${role} project id`),
    parent_version_id:
      version.parent_version_id == null
        ? null
        : requiredText(version.parent_version_id, `${role} parent version id`),
    artifact_digest_sha256: exactDigest(
      version.artifact_digest_sha256,
      `${role} artifact digest sha256`,
    ),
  });
}

function normalizeManifest(files, label) {
  if (!Array.isArray(files)) throw new Error(`${label} manifest must be an array`);
  if (files.length > MAX_MANIFEST_FILES) throw new Error(`${label} manifest exceeds file limit`);
  const byPath = new Map();
  for (const row of files) {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw new Error(`${label} manifest file must be an object`);
    }
    const path = safePath(row.file ?? row.path, `${label} file path`);
    if (byPath.has(path)) throw new Error(`duplicate ${label} manifest path: ${path}`);
    const digest = exactDigest(row.sha256, `${label} file sha256`);
    const byteSize = Number(row.byteSize ?? row.byte_size);
    if (!Number.isSafeInteger(byteSize) || byteSize < 0) {
      throw new Error(`${label} file byte size is invalid`);
    }
    byPath.set(path, Object.freeze({ path, sha256: digest, byte_size: byteSize }));
  }
  return byPath;
}

function surfaceForPath(path) {
  const lower = path.toLowerCase();
  const base = lower.split("/").pop() || lower;
  if (base === "index.html" || /^src\/main\.[^/]+$/.test(lower) || lower === "lib/main.dart") {
    return Object.freeze({ id: "main_experience", label: "main experience" });
  }
  if (
    /\.(css|scss|sass|less)$/.test(lower) ||
    /(^|\/)(styles?|theme|themes|tokens?)(\/|\.|$)/.test(lower)
  ) {
    return Object.freeze({ id: "visual_styling", label: "visual styling" });
  }
  if (/\.(png|jpe?g|webp|gif|svg|ico|woff2?|ttf|otf)$/.test(lower)) {
    return Object.freeze({ id: "visual_assets", label: "visual assets" });
  }
  if (/(^|\/)(components?|widgets?|screens?|pages?|views?|features?)\//.test(lower)) {
    return Object.freeze({ id: "interface_components", label: "interface components" });
  }
  if (
    new Set([
      "package.json",
      "pubspec.yaml",
      "tsconfig.json",
      "jsconfig.json",
      "vite.config.js",
      "vite.config.ts",
      "analysis_options.yaml",
    ]).has(base) ||
    /(^|\/)(config|configs)\//.test(lower)
  ) {
    return Object.freeze({ id: "project_configuration", label: "project configuration" });
  }
  if (/\.(json|ya?ml|csv|md|txt)$/.test(lower)) {
    return Object.freeze({ id: "content_and_data", label: "content and data" });
  }
  if (/\.(js|mjs|cjs|ts|tsx|jsx|dart|kt|swift|py|go|rs|java|cs)$/.test(lower)) {
    return Object.freeze({ id: "app_logic", label: "app source" });
  }
  return Object.freeze({ id: "other_files", label: "other project files" });
}

function changeVerb({ added, modified, removed }) {
  if (added > 0 && modified === 0 && removed === 0) return "Added";
  if (removed > 0 && modified === 0 && added === 0) return "Removed";
  return "Updated";
}

function surfaceStatement(surface) {
  const verb = changeVerb(surface);
  return `${verb} ${surface.label}.`;
}

function listLabels(labels) {
  if (labels.length === 1) return labels[0];
  if (labels.length === 2) return `${labels[0]} and ${labels[1]}`;
  return `${labels.slice(0, -1).join(", ")}, and ${labels.at(-1)}`;
}

function createHumanChangeSummary({ currentVersion, candidateVersion, currentFiles = [], candidateFiles = [] } = {}) {
  const current = normalizeVersion(currentVersion, "current");
  const candidate = normalizeVersion(candidateVersion, "candidate");
  if (current.id === candidate.id) throw new Error("current and candidate versions must differ");
  if (current.organization_id !== candidate.organization_id || current.project_id !== candidate.project_id) {
    throw new Error("current and candidate versions must belong to the same project");
  }
  if (candidate.parent_version_id !== current.id) {
    throw new Error("candidate version is not an exact child of current version");
  }

  const currentManifest = normalizeManifest(currentFiles, "current");
  const candidateManifest = normalizeManifest(candidateFiles, "candidate");
  const paths = [...new Set([...currentManifest.keys(), ...candidateManifest.keys()])].sort((a, b) =>
    a.localeCompare(b, "en"),
  );
  const exactChanges = [];
  for (const path of paths) {
    const before = currentManifest.get(path) ?? null;
    const after = candidateManifest.get(path) ?? null;
    if (before && after && before.sha256 === after.sha256 && before.byte_size === after.byte_size) continue;
    const status = !before ? "ADDED" : !after ? "REMOVED" : "MODIFIED";
    exactChanges.push(Object.freeze({
      path,
      status,
      current_sha256: before?.sha256 ?? null,
      candidate_sha256: after?.sha256 ?? null,
      current_byte_size: before?.byte_size ?? null,
      candidate_byte_size: after?.byte_size ?? null,
    }));
  }

  const grouped = new Map();
  for (const change of exactChanges) {
    const surface = surfaceForPath(change.path);
    const existing = grouped.get(surface.id) ?? {
      surface: surface.id,
      label: surface.label,
      added: 0,
      modified: 0,
      removed: 0,
      file_count: 0,
    };
    existing.file_count += 1;
    if (change.status === "ADDED") existing.added += 1;
    else if (change.status === "REMOVED") existing.removed += 1;
    else existing.modified += 1;
    grouped.set(surface.id, existing);
  }

  const surfaces = [...grouped.values()]
    .sort((a, b) => a.label.localeCompare(b.label, "en"))
    .map((surface) => Object.freeze({
      ...surface,
      statement: surfaceStatement(surface),
    }));

  const labels = surfaces.map((surface) => surface.label);
  const headline = surfaces.length === 0
    ? "No material file changes detected."
    : surfaces.length <= 3
      ? `Updated ${listLabels(labels)}.`
      : `Updated ${surfaces.length} areas, including ${listLabels(labels.slice(0, 3))}.`;

  return Object.freeze({
    schema: "pandora.human-change-summary/1",
    schema_version: 1,
    organization_id: current.organization_id,
    project_id: current.project_id,
    current_version_id: current.id,
    candidate_version_id: candidate.id,
    current_artifact_digest_sha256: current.artifact_digest_sha256,
    candidate_artifact_digest_sha256: candidate.artifact_digest_sha256,
    headline,
    material_change_count: exactChanges.length,
    added_file_count: exactChanges.filter((change) => change.status === "ADDED").length,
    modified_file_count: exactChanges.filter((change) => change.status === "MODIFIED").length,
    removed_file_count: exactChanges.filter((change) => change.status === "REMOVED").length,
    changed_surfaces: Object.freeze(surfaces),
    source_refs: Object.freeze([
      Object.freeze({
        kind: "project_version",
        role: "current",
        id: current.id,
        artifact_digest_sha256: current.artifact_digest_sha256,
      }),
      Object.freeze({
        kind: "project_version",
        role: "candidate",
        id: candidate.id,
        parent_version_id: candidate.parent_version_id,
        artifact_digest_sha256: candidate.artifact_digest_sha256,
      }),
    ]),
    exact_change_refs: Object.freeze(exactChanges),
  });
}

module.exports = { createHumanChangeSummary };
