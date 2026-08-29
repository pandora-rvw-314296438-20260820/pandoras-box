"use strict";

const { createHash } = require("node:crypto");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA40 = /^[0-9a-f]{40}$/i;
const SHA256 = /^[0-9a-f]{64}$/i;
const SAFE_BUCKET = /^[A-Za-z0-9][A-Za-z0-9._-]{0,126}$/;
const MAX_FILES = 1000;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_BUNDLE_BYTES = 25 * 1024 * 1024;
const BUNDLE_KIND = "pandora.runtime-bundle.v1";

function required(value, field, pattern = null) {
  if (typeof value !== "string" || !value.trim() || (pattern && !pattern.test(value.trim()))) throw new Error(`INVALID_${field.toUpperCase()}`);
  return value.trim();
}

function sha256Bytes(value) {
  return createHash("sha256").update(value).digest("hex");
}

function exactBase64(value) {
  if (typeof value !== "string" || value.length === 0 || value.length % 4 !== 0 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new Error("INVALID_ARTIFACT_FILE_BASE64");
  }
  const bytes = Buffer.from(value, "base64");
  if (bytes.toString("base64") !== value) throw new Error("NON_CANONICAL_ARTIFACT_FILE_BASE64");
  return bytes;
}

function safeRelativePath(value) {
  const path = required(value, "artifact_file_path");
  if (path.length > 512 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0") || path.includes("?") || path.includes("#")) {
    throw new Error("UNSAFE_ARTIFACT_FILE_PATH");
  }
  const segments = path.split("/");
  if (!segments.length || segments.some((part) => !part || part === "." || part === ".." || part.length > 255)) throw new Error("UNSAFE_ARTIFACT_FILE_PATH");
  return path;
}

function safeStoragePath(value) {
  const path = required(value, "storage_path");
  if (path.length > 1024 || path.startsWith("/") || path.endsWith("/") || path.includes("\\") || path.includes("\0")) throw new Error("UNSAFE_ARTIFACT_STORAGE_PATH");
  if (path.split("/").some((part) => !part || part === "." || part === "..")) throw new Error("UNSAFE_ARTIFACT_STORAGE_PATH");
  return path;
}

function normalizeArtifactBinding({ organizationId, projectId, projectVersion, artifactVersion, artifact }) {
  const org = required(organizationId, "organization_id", UUID).toLowerCase();
  const project = required(projectId, "project_id", UUID).toLowerCase();
  if (!projectVersion || typeof projectVersion !== "object") throw new Error("PROJECT_VERSION_REQUIRED");
  if (!artifactVersion || typeof artifactVersion !== "object") throw new Error("ARTIFACT_VERSION_REQUIRED");
  if (!artifact || typeof artifact !== "object") throw new Error("ARTIFACT_REQUIRED");

  const versionId = required(projectVersion.id, "project_version_id", UUID).toLowerCase();
  const rootArtifactVersionId = required(projectVersion.root_artifact_version_id ?? projectVersion.rootArtifactVersionId, "root_artifact_version_id", UUID).toLowerCase();
  const buildJobId = required(projectVersion.build_job_id ?? projectVersion.buildJobId, "build_job_id", UUID).toLowerCase();
  const sourceCommit = required(projectVersion.source_commit ?? projectVersion.sourceCommit, "source_commit", SHA40).toLowerCase();
  const artifactDigest = required(projectVersion.artifact_digest_sha256 ?? projectVersion.artifactDigest, "artifact_digest", SHA256).toLowerCase();

  const avId = required(artifactVersion.id, "artifact_version_id", UUID).toLowerCase();
  const avOrg = required(artifactVersion.organization_id ?? artifactVersion.organizationId, "artifact_organization_id", UUID).toLowerCase();
  const avProject = required(artifactVersion.project_id ?? artifactVersion.projectId, "artifact_project_id", UUID).toLowerCase();
  const artifactId = required(artifactVersion.artifact_id ?? artifactVersion.artifactId, "artifact_id", UUID).toLowerCase();
  const contentDigest = required(artifactVersion.content_sha256 ?? artifactVersion.contentSha256, "artifact_content_sha256", SHA256).toLowerCase();
  const storageProvider = required(artifactVersion.storage_provider ?? artifactVersion.storageProvider, "storage_provider").toLowerCase();
  const storageBucket = required(artifactVersion.storage_bucket ?? artifactVersion.storageBucket, "storage_bucket", SAFE_BUCKET);
  const storagePath = safeStoragePath(artifactVersion.storage_path ?? artifactVersion.storagePath);
  const artifactOrg = required(artifact.organization_id ?? artifact.organizationId, "artifact_parent_organization_id", UUID).toLowerCase();
  const artifactProject = required(artifact.project_id ?? artifact.projectId, "artifact_parent_project_id", UUID).toLowerCase();
  const artifactKind = required(artifact.artifact_kind ?? artifact.artifactKind, "artifact_kind").toLowerCase();

  if (rootArtifactVersionId !== avId) throw new Error("ROOT_ARTIFACT_VERSION_MISMATCH");
  if (org !== avOrg || org !== artifactOrg || project !== avProject || project !== artifactProject) throw new Error("ARTIFACT_PROJECT_LINEAGE_MISMATCH");
  if (artifactId !== String(artifact.id || "").toLowerCase()) throw new Error("ARTIFACT_PARENT_MISMATCH");
  if (artifactDigest !== contentDigest) throw new Error("ARTIFACT_DIGEST_MISMATCH");
  if (!new Set(["build_output", "runtime_bundle"]).has(artifactKind)) throw new Error("ARTIFACT_KIND_NOT_DEPLOYABLE");
  if (storageProvider !== "supabase_storage") throw new Error("ARTIFACT_STORAGE_PROVIDER_NOT_SUPPORTED");
  const provenance = artifactVersion.provenance_redacted ?? artifactVersion.provenanceRedacted ?? {};
  if (!provenance || typeof provenance !== "object" || Array.isArray(provenance)) throw new Error("ARTIFACT_PROVENANCE_REQUIRED");
  const producedBuildJobId = required(provenance.buildJobId ?? provenance.build_job_id, "artifact_build_job_id", UUID).toLowerCase();
  const producedProjectVersionId = required(provenance.projectVersionId ?? provenance.project_version_id, "artifact_project_version_id", UUID).toLowerCase();
  const producedSourceCommit = required(provenance.sourceCommit ?? provenance.source_commit, "artifact_source_commit", SHA40).toLowerCase();
  if (producedBuildJobId !== buildJobId || producedProjectVersionId !== versionId || producedSourceCommit !== sourceCommit) throw new Error("ARTIFACT_PROVENANCE_MISMATCH");

  return Object.freeze({ organizationId: org, projectId: project, projectVersionId: versionId, buildJobId, sourceCommit, artifactVersionId: avId, artifactId, artifactDigest, storageProvider, storageBucket, storagePath, artifactKind });
}

function parseRuntimeBundle(raw, expected) {
  const bytes = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
  if (!bytes.length || bytes.length > MAX_BUNDLE_BYTES) throw new Error("ARTIFACT_BUNDLE_SIZE_INVALID");
  const digest = sha256Bytes(bytes);
  if (expected?.artifactDigest && digest !== String(expected.artifactDigest).toLowerCase()) throw new Error("ARTIFACT_BUNDLE_DIGEST_MISMATCH");

  let value;
  try { value = JSON.parse(bytes.toString("utf8")); } catch { throw new Error("ARTIFACT_BUNDLE_JSON_INVALID"); }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("ARTIFACT_BUNDLE_INVALID");
  if (value.kind !== BUNDLE_KIND || value.schemaVersion !== 1) throw new Error("ARTIFACT_BUNDLE_SCHEMA_UNSUPPORTED");
  const projectVersionId = required(value.projectVersionId, "bundle_project_version_id", UUID).toLowerCase();
  const buildJobId = required(value.buildJobId, "bundle_build_job_id", UUID).toLowerCase();
  const sourceCommit = required(value.sourceCommit, "bundle_source_commit", SHA40).toLowerCase();
  if (expected?.projectVersionId && projectVersionId !== String(expected.projectVersionId).toLowerCase()) throw new Error("ARTIFACT_BUNDLE_VERSION_MISMATCH");
  if (expected?.buildJobId && buildJobId !== String(expected.buildJobId).toLowerCase()) throw new Error("ARTIFACT_BUNDLE_BUILD_JOB_MISMATCH");
  if (expected?.sourceCommit && sourceCommit !== String(expected.sourceCommit).toLowerCase()) throw new Error("ARTIFACT_BUNDLE_SOURCE_MISMATCH");
  if (!Array.isArray(value.files) || value.files.length < 1 || value.files.length > MAX_FILES) throw new Error("ARTIFACT_BUNDLE_FILES_INVALID");

  const seen = new Set();
  let prior = null;
  let totalBytes = 0;
  let hasIndex = false;
  const files = value.files.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("ARTIFACT_FILE_INVALID");
    const file = safeRelativePath(entry.file);
    if (seen.has(file)) throw new Error("ARTIFACT_FILE_DUPLICATE");
    if (prior !== null && prior.localeCompare(file, "en") >= 0) throw new Error("ARTIFACT_FILES_NOT_CANONICALLY_SORTED");
    prior = file;
    seen.add(file);
    if (file === "index.html") hasIndex = true;
    if (entry.encoding !== "base64") throw new Error("ARTIFACT_FILE_ENCODING_UNSUPPORTED");
    const fileBytes = exactBase64(entry.data);
    if (fileBytes.length > MAX_FILE_BYTES) throw new Error("ARTIFACT_FILE_TOO_LARGE");
    totalBytes += fileBytes.length;
    if (totalBytes > MAX_BUNDLE_BYTES) throw new Error("ARTIFACT_FILES_TOTAL_TOO_LARGE");
    const fileDigest = required(entry.sha256, "artifact_file_sha256", SHA256).toLowerCase();
    if (sha256Bytes(fileBytes) !== fileDigest) throw new Error("ARTIFACT_FILE_DIGEST_MISMATCH");
    if (!Number.isInteger(entry.byteSize) || entry.byteSize !== fileBytes.length) throw new Error("ARTIFACT_FILE_SIZE_MISMATCH");
    return Object.freeze({ file, data: entry.data, encoding: "base64", sha256: fileDigest, byteSize: fileBytes.length });
  });
  if (!hasIndex) throw new Error("ARTIFACT_ENTRYPOINT_MISSING");
  return Object.freeze({ kind: BUNDLE_KIND, schemaVersion: 1, projectVersionId, buildJobId, sourceCommit, artifactDigest: digest, totalBytes, files: Object.freeze(files) });
}

function toVercelFiles(bundle) {
  if (!bundle || bundle.kind !== BUNDLE_KIND || !Array.isArray(bundle.files)) throw new Error("RUNTIME_BUNDLE_REQUIRED");
  return bundle.files.map(({ file, data }) => Object.freeze({ file, data, encoding: "base64" }));
}

module.exports = { BUNDLE_KIND, MAX_BUNDLE_BYTES, MAX_FILE_BYTES, MAX_FILES, normalizeArtifactBinding, parseRuntimeBundle, safeRelativePath, sha256Bytes, toVercelFiles };
