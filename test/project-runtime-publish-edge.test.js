const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const source = fs.readFileSync("supabase/functions/pandora-project-runtime/index.ts", "utf8");
const start = source.indexOf("async function publishProject");
const end = source.indexOf("\n\nDeno.serve", start);
const publish = source.slice(start, end);

test("customer Publish requires an explicit version and production precondition", () => {
  assert.match(publish, /VERSION_REQUIRED/);
  assert.match(publish, /expectedProductionVersionId/);
  assert.match(publish, /PRODUCTION_PRECONDITION_REQUIRED/);
  assert.match(publish, /PRODUCTION_PRECONDITION_MISMATCH/);
});

test("customer Publish is bound to exact independent verification", () => {
  assert.match(publish, /pandora_verification_runs/);
  assert.match(publish, /verification\.status/);
  assert.match(publish, /PASS/);
  for (const identity of [
    "project_spec_id",
    "project_version_id",
    "build_job_id",
    "source_commit",
    "source_digest",
    "artifact_digest",
    "migration_set_digest",
    "runtime_target_digest",
    "preview_deployment_id",
  ]) assert.match(publish, new RegExp(identity));
  assert.match(publish, /VERIFICATION_STALE/);
});

test("customer Publish promotes the exact preview and never rebuilds production", () => {
  assert.match(publish, /\/promote\/\$\{encodeURIComponent\(previewDeploymentId\)\}/);
  assert.match(publish, /provider_deployment_id: previewDeploymentId/);
  assert.match(publish, /promoted_from_id: preview\.id/);
  assert.doesNotMatch(publish, /createVercelDeployment\([^;]+"production"/s);
  assert.doesNotMatch(publish, /\/v13\/deployments[^\n]+method:\s*"POST"/s);
});

test("customer Publish owns concurrency and ambiguous outcomes durably", () => {
  assert.match(publish, /pandora_runtime_operations/);
  assert.match(publish, /action:\s*"publish_version"/);
  assert.match(publish, /PUBLISH_IN_PROGRESS/);
  assert.match(publish, /status:\s*"uncertain"/);
  assert.match(publish, /PUBLISH_RECONCILIATION_REQUIRED/);
});

test("provider truth writes use server authority after customer ownership is proven", () => {
  const previewStart = source.indexOf("async function createPreview");
  const previewEnd = source.indexOf("\n\nasync function publishProject", previewStart);
  const preview = source.slice(previewStart, previewEnd);
  assert.match(source, /function serviceClient\(\)/);
  assert.match(preview, /const admin = serviceClient\(\);/);
  assert.match(preview, /admin\.from\("pandora_project_versions"\)/);
  assert.match(preview, /admin\.from\("pandora_project_deployments"\)/);
  assert.doesNotMatch(source, /PANDORA_VERCEL_TOKEN/);
  assert.match(source, /pandora_worker_f_vercel_request_20260829/);
});
