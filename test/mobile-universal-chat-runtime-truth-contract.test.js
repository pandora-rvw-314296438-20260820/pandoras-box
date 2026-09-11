"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const migration = readFileSync(
  join(root, "supabase", "migrations", "20260911083500_pandora_universal_chat_runtime_truth_v1.sql"),
  "utf8",
);
const api = readFileSync(
  join(root, "apps", "pandora-mobile", "lib", "core", "data", "pandora_intelligence_api.dart"),
  "utf8",
);
const intelligence = readFileSync(
  join(root, "supabase", "functions", "pandora-intelligence-chat", "index.ts"),
  "utf8",
);

test("Universal Pandora Chat does not require a Project for capability/plugin work", () => {
  assert.match(migration, /pandora_chat_universal_dispatch_v1/);
  assert.match(migration, /'projectRequired',false/);
  assert.match(migration, /Projects are optional persistent context, not a prerequisite/);
  assert.match(migration, /what\[\[:space:\]\]\+can\[\[:space:\]\]\+you\[\[:space:\]\]\+do/);
  assert.match(migration, /plugin\|plugins/);
  assert.match(migration, /return public\.pandora_chat_capability_dispatch_v1/);
});

test("runtime registry exposes human-readable plugin state including Vercel", () => {
  assert.match(migration, /pandora_chat_capability_registry_v2/);
  assert.match(migration, /'vercel'/);
  assert.match(migration, /'Connected'/);
  assert.match(migration, /'Needs authorization'/);
  assert.match(migration, /'Problem'/);
  assert.match(migration, /'Unavailable'/);
  assert.match(migration, /'canUseNow'/);
});

test("mobile routes plugin and capability questions to universal runtime truth", () => {
  assert.match(api, /pandora_chat_universal_dispatch_v3/);
  assert.match(api, /if \(message\.trim\(\)\.isEmpty\) return null/);
  assert.match(api, /if \(payload\['handled'\] != true\) return null/);
});

test("ordinary intelligence prompt treats Projects as optional context", () => {
  assert.match(intelligence, /A Project is optional persistent context, never a prerequisite/);
  assert.match(intelligence, /Projects are optional and do not limit Pandora's general capabilities/);
  assert.doesNotMatch(intelligence, /No project is selected; classify a clear new build as create_project/);
  assert.doesNotMatch(intelligence, /No project context selected\./);
});
