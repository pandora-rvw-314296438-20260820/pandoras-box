"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.join(__dirname, "..");
const ownerApi = fs.readFileSync(
  path.join(root, "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260821024500_projectos_owner_read_completion.sql"),
  "utf8",
);
const rollback = fs.readFileSync(
  path.join(root, "docs/supabase/recovery/jcyqixttuebxqqfkjonq/rollback/20260821024500_remove_projectos_owner_read_completion.sql"),
  "utf8",
);

test("Phase 0 owner read routes only the canonical connected-services intent", () => {
  assert.match(ownerApi, /CONNECTED_SERVICES_OWNER_INTENT/);
  assert.match(ownerApi, /check connected services and tell me what needs attention/);
  assert.match(ownerApi, /CONNECTED_SERVICES_OWNER_OPERATION = "connected_services_health"/);
  assert.match(ownerApi, /ownerReadOperation\(message\)/);
  assert.match(ownerApi, /connections\(context\)/);
  assert.match(ownerApi, /safety\(context\)/);
  assert.match(ownerApi, /projectos_complete_owner_read_intake/);
});

test("free-form intake no longer claims planning before a planner exists", () => {
  assert.doesNotMatch(ownerApi, /Pandora is preparing a safe plan\./);
  assert.doesNotMatch(ownerApi, /Current state and required approvals will be checked next\./);
  assert.match(ownerApi, /no governed planner has started it yet/);
  assert.match(ownerApi, /No execution plan has been created yet/);
  assert.match(ownerApi, /A governed planner route is required before anything can run/);
});

test("owner project summaries fail closed when projection truth is stale", () => {
  assert.match(ownerApi, /const staleAfterMs = staleAfter \? Date\.parse\(staleAfter\) : Number\.NaN/);
  assert.match(ownerApi, /: "stale";/);
  assert.match(ownerApi, /whatIsStoppingUs: dataFreshness === "fresh"/);
  assert.match(ownerApi, /whatIWillDoNext: dataFreshness === "fresh"/);
  assert.match(ownerApi, /project\.repository \?\? projectionProject\.repository/);
});

test("owner read completion is service-role-only, scoped, idempotent and hash-linked", () => {
  assert.match(migration, /private\.assert_control_service_role\(\)/);
  assert.match(migration, /p_operation <> 'connected_services_health'/);
  assert.match(migration, /v_intake\.source <> 'api'/);
  assert.match(migration, /v_intake\.request_type <> 'work'/);
  assert.match(migration, /v_intake\.status = 'completed'/);
  assert.match(migration, /idempotentReplay', true/);
  assert.match(migration, /v_intake\.status <> 'accepted'/);
  assert.match(migration, /public\.record_audit_event/);
  assert.match(migration, /projectos\.owner_read_completed/);
  assert.match(migration, /status = 'completed'/);
  assert.match(migration, /ownerReadResultFingerprint/);
  assert.match(migration, /revoke all on function[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /grant execute on function[\s\S]*to service_role/);
});

test("rollback removes capability but retains historical evidence", () => {
  assert.match(rollback, /Historical intake\/audit evidence is intentionally retained/);
  assert.match(rollback, /drop function if exists public\.projectos_complete_owner_read_intake/);
  assert.doesNotMatch(rollback, /delete from|truncate/i);
});

test("owner intake source remains the canonical api source", () => {
  assert.equal((ownerApi.match(/p_source:\s*"api"/g) || []).length >= 1, true);
  assert.equal(ownerApi.includes("flutterflow_owner_app"), false);
});
