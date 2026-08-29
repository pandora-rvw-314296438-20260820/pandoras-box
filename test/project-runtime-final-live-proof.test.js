"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const migration = fs.readFileSync(
  path.join(process.cwd(), "supabase/migrations/20260829124000_pandora_live_verification_customer_db_v1.sql"),
  "utf8",
);

test("Worker E live verifier independently re-reads exact artifact and provider state", () => {
  assert.match(migration, /pandora_worker_e_verify_runtime_20260829/);
  assert.match(migration, /worker-e-runtime-verifier-v1/);
  assert.match(migration, /builder and verifier must be independent/);
  assert.match(migration, /storage\/v1\/object\/authenticated/);
  assert.match(migration, /content_sha256<>v_ver\.artifact_digest_sha256/);
  assert.match(migration, /extensions\.digest\(convert_to\(coalesce\(v_object\.content,''\),'utf8'\),'sha256'\)/);
  assert.match(migration, /pandora_worker_f_vercel_api_20260829\('GET','\/v13\/deployments\//);
  assert.match(migration, /v_provider_state='READY'/);
  assert.match(migration, /extensions\.http\(\(/);
  assert.match(migration, /bool_and\(status='PASS'\)/);
  assert.match(migration, /required_check_profile/);
  assert.match(migration, /production_exact_version/);
  assert.match(migration, /production_domain/);
  assert.match(migration, /production_runtime/);
});

test("provider reconciliation is polling-safe when account webhooks are unavailable", () => {
  assert.match(migration, /pandora_worker_f_reconcile_deployment_20260829/);
  assert.match(migration, /retry-after/);
  assert.match(migration, /last_provider_check_at=v_now/);
  assert.match(migration, /ready_for_verification/);
  assert.match(migration, /provider_state=v_state/);
});

test("customer database uses the existing isolated resource registries without storing credentials", () => {
  assert.match(migration, /pandora_worker_f_provision_isolated_database_20260829/);
  assert.match(migration, /projectos_project_resources/);
  assert.match(migration, /pandora_runtime_resources/);
  assert.match(migration, /'database','supabase',v_env,'shared_isolated'/);
  assert.match(migration, /create role %I nologin noinherit/);
  assert.match(migration, /revoke all on schema %I from public/);
  assert.match(migration, /customer database role can access Pandora internal tables/);
  assert.match(migration, /'secretStored',false/);
  const resourceConfig = migration.match(/configuration_redacted[\s\S]{0,1200}?jsonb_build_object\([^;]+/i)?.[0] || "";
  assert.doesNotMatch(resourceConfig, /authorizationRef|secretStored|password|token|apiKey/i);
});

test("database migration execution is typed, additive and externally authorized", () => {
  assert.match(migration, /pandora_worker_f_plan_isolated_create_table_20260829/);
  assert.match(migration, /p_table_name !~ '\^\[a-z\]\[a-z0-9_\]\{0,62\}\$'/);
  assert.match(migration, /create_table:/);
  assert.match(migration, /destructive_change/);
  assert.match(migration, /backward_compatible/);
  assert.match(migration, /pandora_worker_e_verify_database_preflight_20260829/);
  assert.match(migration, /Worker E preflight PASS required/);
  assert.match(migration, /p_authorization_ref !~ '\^worker-c:/);
  assert.match(migration, /create table %I\.%I/);
  assert.doesNotMatch(migration, /p_sql\s+text/i);
  assert.doesNotMatch(migration, /execute\s+p_/i);
});

test("database postflight and rollback prove isolation and exact restoration", () => {
  assert.match(migration, /pandora_worker_e_verify_database_postflight_20260829/);
  assert.match(migration, /internalTableAccess/);
  assert.match(migration, /has_table_privilege/);
  assert.match(migration, /pandora_worker_f_rollback_isolated_create_table_20260829/);
  assert.match(migration, /rollback identity mismatch/);
  assert.match(migration, /rollback schema readback mismatch/);
  assert.match(migration, /drop table %I\.%I/);
});
