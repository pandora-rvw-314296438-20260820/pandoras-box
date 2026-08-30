"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const migrationPath = path.join(process.cwd(), "supabase/migrations/20260829123000_pandora_runtime_release_closure_v1.sql");
const sql = fs.readFileSync(migrationPath, "utf8");

test("exact Edge release broker is commit-bound and fail closed", () => {
  assert.match(sql, /p_commit_sha !~ '\^\[0-9a-f\]\{40\}\$'/);
  assert.match(sql, /pandora-project-runtime/);
  assert.match(sql, /pandora-vercel-runtime-webhook/);
  assert.match(sql, /pandora-project-source-generator/);
  assert.match(sql, /Edge function slug outside Pandora release allowlist/);
  assert.match(sql, /pandora_integration_github_api_20260825/);
  assert.match(sql, /\/contents\/.*\?ref='\|\|p_commit_sha/);
  assert.match(sql, /sourceSha256/);
  assert.match(sql, /commitSha/);
});

test("Supabase management credential stays behind the security-definer broker", () => {
  assert.match(sql, /security definer/gi);
  assert.match(sql, /mcpmaster_supabase_account_1_pat/);
  assert.match(sql, /mcpmaster_supabase_account_2_pat/);
  assert.match(sql, /functions\/deploy\?slug=/);
  assert.match(sql, /revoke all on function private\.pandora_release_deploy_edge_from_github_20260829/);
  assert.match(sql, /grant execute on function private\.pandora_release_deploy_edge_from_github_20260829\(text,text\) to service_role/);
  const releaseBroker = sql.slice(
    sql.indexOf("create or replace function private.pandora_release_deploy_edge_from_github_20260829"),
    sql.indexOf("create or replace function public.pandora_release_deploy_edge_from_github_20260829"),
  );
  const releaseReturn = releaseBroker.slice(releaseBroker.lastIndexOf("return jsonb_build_object("));
  assert.match(releaseReturn, /'sourceSha256',v_source_sha/);
  assert.doesNotMatch(releaseReturn, /decrypted_secret|v_token|authorization|Bearer /i);
});

test("Vercel broker returns only safe retry and rate-limit headers", () => {
  assert.match(sql, /retry-after/);
  assert.match(sql, /x-ratelimit-limit/);
  assert.match(sql, /x-ratelimit-remaining/);
  assert.match(sql, /x-ratelimit-reset/);
  assert.match(sql, /'headers',v_safe_headers/);
  assert.match(sql, /where lower\(h\.field\) in \('retry-after','x-ratelimit-limit','x-ratelimit-remaining','x-ratelimit-reset'\)/);
  const safeHeaderClause = sql.match(/where lower\(h\.field\) in \([^;]+;/)?.[0] || "";
  assert.doesNotMatch(safeHeaderClause, /authorization|cookie|set-cookie/i);
});


test("Worker D runtime-bundle finalizer validates storage and durable lineage", () => {
  assert.match(sql, /pandora_finalize_runtime_bundle_20260829/);
  assert.match(sql, /pandora\.runtime-bundle\.v1/);
  assert.match(sql, /pandora-build-artifacts/);
  assert.match(sql, /storage\/v1\/object\/authenticated\/pandora-build-artifacts/);
  assert.match(sql, /runtime artifact storage readback mismatch/);
  assert.match(sql, /root_artifact_version_id=v_artifact_version_id/);
  assert.match(sql, /artifact_digest_sha256=v_bundle_sha/);
  assert.match(sql, /status='waiting_verification',current_stage='verifying'/);
  assert.match(sql, /produced_by_build_step_id/);
  assert.match(sql, /project version already bound to different runtime artifact/);
  assert.match(sql, /grant execute on function private\.pandora_finalize_runtime_bundle_20260829\(uuid,uuid,uuid,text\) to service_role/);
});

test("runtime-bundle finalizer never demotes a terminal build job", () => {
  const finalizer = sql.slice(sql.indexOf("create or replace function private.pandora_finalize_runtime_bundle_20260829"));
  assert.match(finalizer, /status not in \('claimed','running','waiting_verification'\)/);
  assert.match(finalizer, /status in \('claimed','running','waiting_verification'\)/);
  assert.doesNotMatch(finalizer, /status in \('claimed','running','waiting_verification','succeeded'\)/);
});


test("exact Edge release broker explicitly allows the source convergence worker with its custom-auth mode", () => {
  const forwardSql = fs.readFileSync(
    path.join(process.cwd(), "supabase/migrations/20260831052000_pandora_source_convergence_release_allowlist_v1.sql"),
    "utf8",
  );
  assert.match(forwardSql, /when 'pandora-source-convergence-worker' then/);
  assert.match(forwardSql, /supabase\/functions\/pandora-source-convergence-worker\/index\.ts/);
  assert.match(forwardSql, /v_verify_jwt := false/);
  assert.match(forwardSql, /Edge function slug outside Pandora release allowlist/);
});
