"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const source = readFileSync(join(__dirname, "..", "supabase", "functions", "pandora-project-runtime", "index.ts"), "utf8");

function block(start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0, `missing ${start}`);
  assert.ok(b > a, `missing ${end}`);
  return source.slice(a, b);
}

test("preview consumes an existing exact artifact-backed version instead of synthesizing source", () => {
  const preview = block("async function createPreview", "async function publishProject");
  assert.match(preview, /loadExactRuntimeBundle\(context, projectId, versionId, requestedArtifactDigest\)/);
  assert.match(preview, /idempotency_key: operationKey/);
  assert.match(preview, /artifact_digest: bundle\.artifactDigest/);
  assert.match(preview, /source_commit_sha: bundle\.sourceCommit/);
  assert.match(preview, /verification_state: verificationState/);
  assert.doesNotMatch(preview, /pandora_project_versions"\)\s*\.insert/);
  assert.doesNotMatch(preview, /previewHtml\(/);
});

test("artifact loader binds the durable root artifact, private Storage bytes, provenance and every file digest", () => {
  const loader = block("async function loadExactRuntimeBundle", "function exactPreviewMeta");
  assert.match(loader, /root_artifact_version_id/);
  assert.match(loader, /pandora_artifact_versions/);
  assert.match(loader, /pandora_artifacts/);
  assert.match(loader, /storage_provider/);
  assert.match(loader, /admin\.storage\.from\(coordinate\.bucket\)\.download\(coordinate\.path\)/);
  assert.match(loader, /sha256BytesHex\(bytes\)/);
  assert.match(loader, /ARTIFACT_PROVENANCE_MISMATCH/);
  assert.match(loader, /ARTIFACT_BUNDLE_DIGEST_MISMATCH/);
  assert.match(loader, /ARTIFACT_FILE_DIGEST_MISMATCH/);
  assert.match(loader, /ARTIFACT_ENTRYPOINT_MISSING/);
});

test("provider READY maps only to ready_for_verification and ambiguous create is reconciled by operation metadata", () => {
  const preview = block("async function createPreview", "async function publishProject");
  const provider = block("async function findVercelDeploymentByOperation", "async function createProject");
  assert.match(provider, /pandoraOperationId/);
  assert.match(provider, /\/v6\/deployments\?projectId=/);
  assert.match(provider, /PREVIEW_RECONCILIATION_REQUIRED/);
  assert.match(preview, /ready \? "ready_for_verification"/);
  assert.match(preview, /verificationState = ready \? "ready_for_verification"/);
  assert.doesNotMatch(preview, /live_verified/);
});

test("preview API requires an explicit request body and exact version lineage", () => {
  assert.match(source, /createPreview\(context, decodeURIComponent\(previewMatch\[1\]\), await bodyJson\(req\)\)/);
  assert.match(source, /const versionId = textValue\(body\.versionId\)/);
  assert.match(source, /const requestedArtifactDigest = textValue\(body\.artifactDigest\)/);
  assert.match(source, /const idempotencyRef = textValue\(body\.idempotencyKey\)/);
  assert.match(source, /const authorizationRef = textValue\(body\.authorizationRef\)/);
});
