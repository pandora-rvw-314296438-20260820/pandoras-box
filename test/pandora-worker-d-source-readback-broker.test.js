import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const edge = fs.readFileSync(
  "supabase/functions/pandora-source-convergence-worker/index.ts",
  "utf8",
);
const legacyMigration = fs.readFileSync(
  "supabase/migrations/20260905093000_pandora_worker_d_source_readback_broker_v1.sql",
  "utf8",
);
const rebindMigration = fs.readFileSync(
  "supabase/migrations/20260906032950_pandora_worker_d_readback_shared_runtime_v1.sql",
  "utf8",
);
const config = fs.readFileSync("supabase/config.toml", "utf8");

test("Worker D readback keeps service-role material inside the shared source runtime", () => {
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /pandora_validate_source_worker_key_20260831/);
  assert.match(edge, /x-pandora-internal-key/);
  assert.match(edge, /async function readbackWorkerDSource/);
  assert.doesNotMatch(edge, /api-keys\?reveal=true/);
  assert.doesNotMatch(edge, /mcpmaster_supabase_account_[12]_pat/);
});

test("shared readback identity is derived from the build job and exact artifact lineage", () => {
  assert.match(edge, /exactKeys\(body, \["buildJobId"\]\)/);
  assert.match(edge, /readbackWorkerDSource\(admin, text\(body\.buildJobId\)\)/);
  assert.match(edge, /pandora_build_jobs/);
  assert.match(edge, /pandora_project_versions/);
  assert.match(edge, /pandora_artifact_versions/);
  assert.match(edge, /pandora_artifacts/);
  assert.match(edge, /artifact_kind !== "source_snapshot"/);
  assert.match(edge, /worker_identity !== "pandora-worker-d-static-web"/);
  assert.match(edge, /lease_expires_at/);
});

test("shared runtime requires exact source byte and digest readback", () => {
  assert.match(edge, /bytes\.byteLength !== Number\(av\.byte_size\)/);
  assert.match(edge, /sha256Bytes\(bytes\) !== av\.content_sha256/);
  assert.match(edge, /SOURCE_READBACK_MISMATCH/);
  assert.match(edge, /SOURCE_READBACK_UNSAFE/);
  assert.match(legacyMigration, /STATIC_BUILD_SOURCE_READBACK_MISMATCH/);
});

test("historical dedicated broker is explicitly rebound to the shared runtime", () => {
  assert.match(legacyMigration, /pandora-worker-d-source-readback/);
  assert.match(rebindMigration, /pandora-source-convergence-worker/);
  assert.match(rebindMigration, /pandora-worker-d-source-readback/);
  assert.match(rebindMigration, /WORKER_D_READBACK_REBIND_VERIFY_FAILED/);
});

test("Supabase config deploys only the shared source runtime for Worker D readback", () => {
  assert.match(
    config,
    /\[functions\.pandora-source-convergence-worker\]\s*verify_jwt\s*=\s*false/,
  );
  assert.doesNotMatch(config, /\[functions\.pandora-worker-d-source-readback\]/);
  assert.equal(
    fs.existsSync("supabase/functions/pandora-worker-d-source-readback/index.ts"),
    false,
  );
});
