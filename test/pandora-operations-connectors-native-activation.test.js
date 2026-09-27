"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const worker = fs.readFileSync(path.join(root, "api/operations-native-worker.ts"), "utf8");
const control = fs.readFileSync(
  path.join(root, "supabase/functions/mcpmaster-supabase-control/index.ts"),
  "utf8",
);
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260926014024_pandora_operations_native_worker_activation_v1.sql"),
  "utf8",
);

test("native worker stays in canonical Operations scope while admitting bounded generic source tasks", () => {
  assert.match(worker, /operations_generic_source_candidate/);
  assert.match(worker, /operations_generic_source_execute/);
  assert.match(worker, /operations_generic_source_release_step/);
  assert.match(worker, /pandora-native-builder-v1/);
  assert.match(worker, /operations_wake_authorize/);
  assert.match(worker, /operations_reconcile/);
  assert.doesNotMatch(worker, /operations_control/);
  assert.doesNotMatch(worker, /noProduction\s*:\s*false/);
});

test("Vercel OIDC control bridge owns worker and project identity", () => {
  assert.match(control, /ee282126-3f61-4058-8c92-2fedbfcecf1f/);
  assert.match(control, /vercel:mcpmaster:operations-native-builder-v1/);
  assert.match(control, /vercel:mcpmaster:operations-native-release-v1/);
  assert.match(control, /pandora_ops_register_native_worker_v1/);
  assert.match(control, /pandora_ops_wake_authorize_v1/);
  assert.match(control, /pandora_ops_reconcile_required_v1/);
  assert.doesNotMatch(control, /p_organization_id:\s*input/);
  assert.doesNotMatch(control, /p_project_id:\s*input/);
});

test("native worker schema keeps ChatGPT identity and adds a distinct engine", () => {
  assert.match(migration, /engine in \('chatgpt','pandora_native'\)/);
  assert.match(migration, /'pandora_native'/);
  assert.match(migration, /revoke all on function public\.pandora_ops_register_native_worker_v1/);
  assert.match(migration, /grant execute on function public\.pandora_ops_register_native_worker_v1[\s\S]*to service_role/);
});

test("wake credential stays in Supabase Vault and is compared by digest", () => {
  assert.match(migration, /pandora_ops_wake_token_v1/);
  assert.match(migration, /vault\.create_secret/);
  assert.match(migration, /extensions\.digest/);
  assert.match(migration, /p_token_sha256/);
  assert.doesNotMatch(worker, /pandora_ops_wake_token_v1/);
});

test("generic source work claims before execution and reconciles ambiguous post-claim failures", () => {
  const releaseAt = worker.indexOf('action: "operations_generic_source_release_step"');
  const candidateAt = worker.indexOf('action: "operations_generic_source_candidate"');
  const claimAt = worker.indexOf('action: "operations_claim"');
  const executeAt = worker.indexOf('action: "operations_generic_source_execute"');
  const reconcileAt = worker.indexOf('action: "operations_reconcile"');
  assert.ok(releaseAt >= 0 && candidateAt > releaseAt);
  assert.ok(claimAt > candidateAt && executeAt > claimAt);
  assert.ok(reconcileAt > executeAt);
  assert.match(worker, /GENERIC_SOURCE_EXECUTION_UNCONFIRMED/);
});
