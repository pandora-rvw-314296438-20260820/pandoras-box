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
  assert.doesNotMatch(sql, /return jsonb_build_object\([\s\S]{0,600}(decrypted_secret|v_token)/i);
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
