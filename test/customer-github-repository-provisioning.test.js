"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const migration = fs.readFileSync(
  path.join(process.cwd(), "supabase/migrations/20260901054500_pandora_customer_repo_provisioning_v1.sql"),
  "utf8",
);

test("new Simple Mode projects provision a bounded private GitHub repository", () => {
  assert.match(migration, /Github_supabase/);
  assert.match(migration, /https:\/\/api\.github\.com\/user\/repos/);
  assert.match(migration, /'private',true/);
  assert.match(migration, /\^pandora-\[a-z0-9\]/);
  assert.match(migration, /createdFrom.*simple_mode/s);
  assert.match(migration, /before insert on public\.projectos_projects/);
  assert.match(migration, /new\.repository := v_full_name/);
});

test("repo provisioning does not widen the generic Pandora GitHub transport", () => {
  assert.doesNotMatch(migration, /create or replace function private\.pandora_integration_github_api_20260825/i);
  assert.doesNotMatch(migration, /\/orgs\/[^'\s]+\/repos/);
  assert.match(migration, /pandora-rvw-314296438-20260820/);
});
