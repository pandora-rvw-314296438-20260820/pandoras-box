"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("active Universal Chat no longer falls through to ProjectOS", () => {
  const migration = read("supabase/migrations/20260914050000_pandora_projectos_retirement_v1.sql");
  assert.match(migration, /create or replace function public\.pandora_chat_universal_dispatch_v9/);
  assert.match(migration, /'routing','pandora_native_intelligence'/);
  assert.match(migration, /'source','project_workspace_change'/);
  const functionBody = migration.split("$body$")[1] || "";
  assert.doesNotMatch(functionBody, /return\s+public\.pandora_chat_universal_dispatch_v8/i);
  assert.doesNotMatch(functionBody, /projectos_accept_intake/i);
  assert.doesNotMatch(functionBody, /'source','projectos_intake'/i);
});

test("production execution ledger does not automatically create ProjectOS intake", () => {
  const ledger = read("src/runtime/execution-ledger-client.js");
  assert.match(ledger, /this\.intakeProvider = options\.intakeProvider \|\| undefined/);
  assert.doesNotMatch(ledger, /shouldEnforceMandatoryIntake/);
  assert.doesNotMatch(ledger, /new .*ProjectOSExecutionIntakeProvider/);
  assert.doesNotMatch(ledger, /Mandatory ProjectOS intake is required/);
});

test("continuous executor is exported from Pandora intelligence", () => {
  const index = read("packages/pandora-intelligence/src/index.js");
  assert.match(index, /require\('\.\/runtime\/index\.js'\)/);
  const runtime = require(path.join(root, "packages/pandora-intelligence/src/index.js"));
  assert.equal(typeof runtime.runContinuousExecution, "function");
});

test("owner-facing runtime copy no longer instructs ProjectOS routing", () => {
  const plugins = read("apps/pandora-mobile/lib/features/plugins/plugins_screen.dart");
  const exactSource = read("apps/pandora-mobile/lib/features/command/exact_source_verification_card.dart");
  const http = read("src/http-app.js");
  assert.doesNotMatch(plugins, /Route every consequential change through ProjectOS/);
  assert.match(plugins, /Pandoraâ€™s governed runtime/);
  assert.doesNotMatch(exactSource, /canonical ProjectOS project ID/);
  assert.match(http, /internal Pandora runtime error/);
});
