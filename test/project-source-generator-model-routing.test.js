"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const generator = fs.readFileSync(path.join(process.cwd(), "supabase/functions/pandora-project-source-generator/index.ts"), "utf8");
const migration = fs.readFileSync(path.join(process.cwd(), "supabase/migrations/20260829124000_pandora_live_verification_customer_db_v1.sql"), "utf8");

test("source generation defaults to the live-proven bounded Gemini route", () => {
  assert.match(generator, /PANDORA_SOURCE_GENERATION_MODEL\"\) \|\| \"gemini-3\.5-flash-lite\"/);
  assert.match(migration, /http_set_curlopt\('CURLOPT_TIMEOUT_MS','30000'\)/);
  assert.match(migration, /http_set_curlopt\('CURLOPT_CONNECTTIMEOUT_MS','5000'\)/);
  assert.doesNotMatch(migration.slice(migration.lastIndexOf("CREATE OR REPLACE FUNCTION private.pandora_worker_b_gemini_api_20260829")), /set_config\('http\.curlopt_timeout_ms'/);
});
