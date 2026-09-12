"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const migration = readFileSync(
  join(root, "supabase", "migrations", "20260911135500_pandora_governed_provider_reads_v1.sql"),
  "utf8",
);
const mobile = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "data", "pandora_intelligence_api.dart"),
  "utf8",
);

test("governed read gateway is bounded and provider allowlisted", () => {
  assert.match(migration, /pandora_governed_provider_read_v1/);
  assert.match(migration, /v_provider not in \('github','supabase','vercel'\)/);
  assert.match(migration, /repository\.read/);
  assert.match(migration, /pull_request\.read/);
  assert.match(migration, /project\.read/);
  assert.match(migration, /deployment\.read/);
  assert.match(migration, /repository_not_allowlisted/);
  assert.match(migration, /supabase_project_not_allowlisted/);
  assert.match(migration, /vercel_project_not_allowlisted/);
});

test("provider credentials remain behind governed adapters", () => {
  assert.match(migration, /private\.pandora_integration_github_api_20260825/);
  assert.match(migration, /private\.pandora_worker_f_vercel_api_20260829/);
  assert.match(migration, /vault\.decrypted_secrets/);
  assert.doesNotMatch(migration, /return\s+v_token/i);
  assert.doesNotMatch(migration, /'token'\s*,\s*v_token/i);
});

test("chat read lane emits verified evidence and fails closed", () => {
  assert.match(migration, /pandora_chat_universal_dispatch_v3/);
  assert.match(migration, /authority','governed_adapter/);
  assert.match(migration, /Pandora will not substitute cached or invented state/);
  assert.match(migration, /return public\.pandora_chat_universal_dispatch_v2/);
  assert.match(migration, /ProjectRequired|projectRequired/);
});

test("mobile invokes the governed universal dispatch", () => {
  assert.match(mobile, /pandora_chat_universal_dispatch_v6/);
  assert.doesNotMatch(mobile, /pandora_chat_universal_dispatch_v2/);
});
