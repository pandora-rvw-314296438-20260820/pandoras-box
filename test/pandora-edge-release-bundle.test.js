"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260907063000_pandora_owner_api_exact_source_bundle_v1.sql",
);
const sql = fs.readFileSync(migrationPath, "utf8");

test("owner API exact-source release includes every local dependency", () => {
  assert.match(sql, /when 'pandora-owner-api' then/);
  assert.match(sql, /v_import_map_path := 'deno\.json'/);
  assert.match(
    sql,
    /array\['contract\.ts','command-pipeline\.mjs','operational-workspace\.mjs'\]/,
  );
  assert.match(sql, /exact Edge sibling source unavailable at requested commit/);
  assert.match(sql, /filename="'\|\|/);
  assert.match(sql, /filename="deno\.json"/);
});

test("owner API bundle remains exact-commit bound and fail closed", () => {
  assert.match(sql, /p_commit_sha !~ '\^\[0-9a-f\]\{40\}\$'/);
  assert.match(sql, /\?ref='\|\|p_commit_sha/);
  assert.match(sql, /Edge function slug outside Pandora release allowlist/);
  assert.match(sql, /multipart boundary collision in sibling source/);
  assert.match(sql, /verify_jwt',v_verify_jwt/);
  assert.match(sql, /'sourceSha256',v_source_sha/);
});

test("release response still cannot expose Vault credentials", () => {
  const releaseReturn = sql.slice(sql.lastIndexOf("return jsonb_build_object("));
  assert.doesNotMatch(
    releaseReturn,
    /decrypted_secret|v_token|authorization|Bearer /i,
  );
});
