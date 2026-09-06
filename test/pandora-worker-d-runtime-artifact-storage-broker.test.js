import fs from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const edge = fs.readFileSync(
  "supabase/functions/pandora-source-convergence-worker/index.ts",
  "utf8",
);
const migration = fs.readFileSync(
  "supabase/migrations/20260906072000_pandora_worker_d_runtime_artifact_storage_broker_v1.sql",
  "utf8",
);
const ledgerMigration = fs.readFileSync(
  "supabase/migrations/20260829177000_pandora_runtime_bundle_ledger_state_fix_v1.sql",
  "utf8",
);

test("Worker D runtime persistence stays inside the existing service-role Edge boundary", () => {
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /RUNTIME_BUNDLE_MEDIA_TYPE/);
  assert.match(edge, /application\/vnd\.pandora\.runtime-bundle\+json/);
  assert.match(edge, /persistWorkerDRuntimeBundle/);
  assert.match(edge, /x-pandora-build-job-id/);
  assert.match(edge, /x-pandora-build-step-id/);
  assert.match(edge, /x-pandora-runtime-sha256/);
  assert.match(edge, /x-pandora-runtime-byte-size/);
  assert.match(edge, /pandora-worker-d-static-web/);
  assert.match(edge, /lease_expires_at/);
  const runtimePersist = edge.slice(
    edge.indexOf("async function persistWorkerDRuntimeBundle"),
    edge.indexOf("Deno.serve"),
  );
  assert.doesNotMatch(runtimePersist, /pandora_build_job_steps/);
  assert.match(runtimePersist, /buildStepId/);
  assert.match(edge, /pandora\.runtime-bundle\.v1/);
  assert.match(edge, /admin\.storage\.from\(BUCKET\)\.upload/);
  assert.match(edge, /admin\.storage\.from\(BUCKET\)\.download/);
  assert.doesNotMatch(edge, /api-keys\?reveal=true/);
  assert.doesNotMatch(edge, /mcpmaster_supabase_account_[12]_pat/);
});

test("runtime finalizer owns build-step validation before crossing the Edge transaction boundary", () => {
  assert.match(ledgerMigration, /select \* into v_step from public\.pandora_build_job_steps/);
  assert.match(ledgerMigration, /v_step\.status<>'succeeded'/);
  assert.match(ledgerMigration, /v_step\.build_job_id<>v_job\.id/);
});

test("runtime finalizer migration removes Management PAT discovery and verifies exact broker receipt", () => {
  assert.match(migration, /pandora_finalize_runtime_bundle_20260829/);
  assert.match(migration, /pandora_source_worker_internal_20260831/);
  assert.match(migration, /pandora-source-convergence-worker/);
  assert.match(migration, /application\/vnd\.pandora\.runtime-bundle\+json/);
  assert.match(migration, /x-pandora-build-job-id/);
  assert.match(migration, /x-pandora-build-step-id/);
  assert.match(migration, /x-pandora-runtime-sha256/);
  assert.match(migration, /x-pandora-runtime-byte-size/);
  assert.match(migration, /p_bundle::varchar/);
  assert.match(migration, /runtime_persisted/);
  assert.match(migration, /storageProvider/);
  assert.match(migration, /storageBucket/);
  assert.match(migration, /storagePath/);
  assert.match(migration, /api-keys\?reveal=true/);
  assert.match(migration, /mcpmaster_supabase_account_1_pat/);
  assert.match(migration, /mcpmaster_supabase_account_2_pat/);
  assert.match(migration, /position\('api-keys\?reveal=true' in v_def\) > 0/);
  assert.match(migration, /position\('mcpmaster_supabase_account_1_pat' in v_def\) > 0/);
  assert.match(migration, /position\('mcpmaster_supabase_account_2_pat' in v_def\) > 0/);
});
