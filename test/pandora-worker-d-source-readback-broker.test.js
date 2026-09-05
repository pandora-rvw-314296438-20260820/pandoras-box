import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const edge = fs.readFileSync(
  "supabase/functions/pandora-worker-d-source-readback/index.ts",
  "utf8",
);
const migration = fs.readFileSync(
  "supabase/migrations/20260905093000_pandora_worker_d_source_readback_broker_v1.sql",
  "utf8",
);
const config = fs.readFileSync("supabase/config.toml", "utf8");

test("Worker D readback broker keeps service-role material server-side", () => {
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /pandora_validate_source_worker_key_20260831/);
  assert.match(edge, /x-pandora-internal-key/);
  assert.doesNotMatch(edge, /api-keys\?reveal=true/);
  assert.doesNotMatch(edge, /mcpmaster_supabase_account_[12]_pat/);
  assert.doesNotMatch(edge, /service_role.*response/i);
});

test("readback identity is derived from the build job, not caller storage input", () => {
  assert.match(edge, /exactKeys\(body, \["buildJobId"\]\)/);
  assert.match(edge, /pandora_build_jobs/);
  assert.match(edge, /pandora_project_versions/);
  assert.match(edge, /pandora_artifact_versions/);
  assert.match(edge, /pandora_artifacts/);
  assert.match(edge, /artifact_kind !== "source_snapshot"/);
  assert.match(edge, /worker_identity !== "pandora-worker-d-static-web"/);
  assert.match(edge, /lease_expires_at/);
  assert.doesNotMatch(edge, /body\.(?:storagePath|storageBucket|organizationId|projectId)/);
});

test("success requires exact source byte and digest readback", () => {
  assert.match(edge, /bytes\.byteLength !== Number\(av\.byte_size\)/);
  assert.match(edge, /sha256Bytes\(bytes\) !== av\.content_sha256/);
  assert.match(migration, /byteSize.*v_source\.byte_size/s);
  assert.match(migration, /sourceText/);
  assert.match(migration, /STATIC_BUILD_SOURCE_READBACK_MISMATCH/);
});

test("migration replaces only the exact predecessor function definition", () => {
  assert.match(migration, /f6d7149b9e7ba30aff67d08331bfdd97b048bd9934fd2f01dcd1a2f09ef398fd/);
  assert.match(migration, /STATIC_BUILD_PREDECESSOR_IDENTITY_MISMATCH/);
  assert.match(migration, /pandora_source_worker_internal_20260831/);
  assert.match(migration, /pandora-worker-d-source-readback/);
});

test("custom internal auth is explicit in Supabase function config", () => {
  assert.match(
    config,
    /\[functions\.pandora-worker-d-source-readback\]\s*verify_jwt\s*=\s*false/,
  );
});
