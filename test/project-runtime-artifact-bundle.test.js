const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { normalizeArtifactBinding, parseRuntimeBundle, toVercelFiles } = require("../packages/pandora-project-runtime/src/artifact-bundle.js");

const ids = {
  org: "11111111-1111-4111-8111-111111111111",
  project: "22222222-2222-4222-8222-222222222222",
  version: "33333333-3333-4333-8333-333333333333",
  artifactVersion: "44444444-4444-4444-8444-444444444444",
  artifact: "55555555-5555-4555-8555-555555555555",
  build: "66666666-6666-4666-8666-666666666666",
};
const sourceCommit = "a".repeat(40);
const hash = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
const file = (name, text) => {
  const bytes = Buffer.from(text);
  return { file: name, data: bytes.toString("base64"), encoding: "base64", sha256: hash(bytes), byteSize: bytes.length };
};
function bundleBytes(overrides = {}) {
  return Buffer.from(JSON.stringify({
    kind: "pandora.runtime-bundle.v1",
    schemaVersion: 1,
    projectVersionId: ids.version,
    buildJobId: ids.build,
    sourceCommit,
    files: [file("assets/app.js", "console.log('ok')"), file("index.html", "<!doctype html><main>ok</main>")],
    ...overrides,
  }));
}
function bindingRows(digest) {
  return {
    organizationId: ids.org,
    projectId: ids.project,
    projectVersion: { id: ids.version, root_artifact_version_id: ids.artifactVersion, build_job_id: ids.build, source_commit: sourceCommit, artifact_digest_sha256: digest },
    artifactVersion: { id: ids.artifactVersion, organization_id: ids.org, project_id: ids.project, artifact_id: ids.artifact, content_sha256: digest, storage_provider: "supabase_storage", storage_bucket: "pandora-build-artifacts", storage_path: `${ids.org}/${ids.project}/${ids.version}/runtime-bundle.json`, provenance_redacted: { buildJobId: ids.build, projectVersionId: ids.version, sourceCommit } },
    artifact: { id: ids.artifact, organization_id: ids.org, project_id: ids.project, artifact_kind: "runtime_bundle" },
  };
}

test("exact Worker D runtime bundle binds durable artifact lineage and Vercel files", () => {
  const raw = bundleBytes();
  const digest = hash(raw);
  const binding = normalizeArtifactBinding(bindingRows(digest));
  const parsed = parseRuntimeBundle(raw, binding);
  assert.equal(parsed.artifactDigest, digest);
  assert.equal(parsed.projectVersionId, ids.version);
  assert.equal(parsed.buildJobId, ids.build);
  assert.deepEqual(toVercelFiles(parsed).map(({ file, encoding }) => ({ file, encoding })), [
    { file: "assets/app.js", encoding: "base64" },
    { file: "index.html", encoding: "base64" },
  ]);
});

test("artifact binding rejects root artifact, digest, project and Worker D provenance drift", () => {
  const raw = bundleBytes();
  const digest = hash(raw);
  const cases = [
    (rows) => { rows.projectVersion.root_artifact_version_id = "77777777-7777-4777-8777-777777777777"; },
    (rows) => { rows.projectVersion.artifact_digest_sha256 = "b".repeat(64); },
    (rows) => { rows.artifactVersion.project_id = "77777777-7777-4777-8777-777777777777"; },
    (rows) => { rows.artifactVersion.provenance_redacted.buildJobId = "77777777-7777-4777-8777-777777777777"; },
  ];
  for (const mutate of cases) {
    const rows = bindingRows(digest); mutate(rows);
    assert.throws(() => normalizeArtifactBinding(rows));
  }
});

test("runtime bundle rejects bundle digest and exact identity drift", () => {
  const raw = bundleBytes();
  const digest = hash(raw);
  const binding = normalizeArtifactBinding(bindingRows(digest));
  assert.throws(() => parseRuntimeBundle(raw, { ...binding, artifactDigest: "c".repeat(64) }), /DIGEST/);
  assert.throws(() => parseRuntimeBundle(bundleBytes({ projectVersionId: "77777777-7777-4777-8777-777777777777" }), binding));
  assert.throws(() => parseRuntimeBundle(bundleBytes({ buildJobId: "77777777-7777-4777-8777-777777777777" }), binding));
  assert.throws(() => parseRuntimeBundle(bundleBytes({ sourceCommit: "b".repeat(40) }), binding));
});

test("runtime bundle rejects traversal, duplicate, unsorted, missing entrypoint and tampered file bytes", () => {
  const base = { kind: "pandora.runtime-bundle.v1", schemaVersion: 1, projectVersionId: ids.version, buildJobId: ids.build, sourceCommit };
  const badBundles = [
    { ...base, files: [file("../index.html", "x")] },
    { ...base, files: [file("index.html", "x"), file("index.html", "y")] },
    { ...base, files: [file("index.html", "x"), file("assets/app.js", "y")] },
    { ...base, files: [file("assets/app.js", "x")] },
    { ...base, files: [{ ...file("index.html", "x"), sha256: "d".repeat(64) }] },
  ];
  for (const value of badBundles) assert.throws(() => parseRuntimeBundle(Buffer.from(JSON.stringify(value))));
});

test("artifact storage must be private canonical Supabase storage coordinates", () => {
  const raw = bundleBytes(); const digest = hash(raw);
  for (const mutate of [
    (rows) => { rows.artifactVersion.storage_provider = "http"; },
    (rows) => { rows.artifactVersion.storage_path = "../bundle.json"; },
    (rows) => { rows.artifactVersion.storage_bucket = "bad/bucket"; },
  ]) {
    const rows = bindingRows(digest); mutate(rows);
    assert.throws(() => normalizeArtifactBinding(rows));
  }
});
