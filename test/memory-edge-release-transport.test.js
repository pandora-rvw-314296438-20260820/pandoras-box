
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260904125641_pandora_memory_edge_release_transport_v1.sql",
);
const sql = fs.readFileSync(migrationPath, "utf8");

test("Memory Edge release transport is exact-main, signed-source and fixed-target only", () => {
  assert.match(sql, /pandoras-box-memory\/branches\/main/);
  assert.match(sql, /requested Memory commit is not current main/);
  assert.match(sql, /Memory main signature verification required/);
  assert.match(sql, /pandoras-box-memory\/contents\/supabase\/functions\/pandora-projectos-bridge\/index\.ts\?ref=/);
  assert.match(sql, /pandoras-box-memory\/contents\/supabase\/functions\/pandora-projectos-bridge\/deno\.json\?ref=/);
  assert.match(sql, /ivmvufhcsezyhczzondn/);
  assert.match(sql, /functions\/deploy\?slug=pandora-projectos-bridge/);
  assert.match(sql, /'verify_jwt',false/);
});

test("Memory Edge release transport keeps provider credentials server-side", () => {
  assert.match(sql, /pandora_integration_github_api_20260825/);
  assert.match(sql, /mcpmaster_supabase_account_1_pat/);
  assert.match(sql, /mcpmaster_supabase_account_2_pat/);
  assert.match(sql, /security definer/gi);
  assert.match(sql, /revoke all on function private\.pandora_memory_release_deploy_projectos_bridge_20260904\(text\) from public,anon,authenticated/);
  assert.match(sql, /grant execute on function public\.pandora_memory_release_deploy_projectos_bridge_v1\(text\) to service_role/);
  const safeReturn = sql.slice(sql.lastIndexOf("return jsonb_build_object("));
  assert.match(safeReturn, /'sourceSha256',v_source_sha/);
  assert.match(safeReturn, /'denoSha256',v_deno_sha/);
  assert.match(safeReturn, /'treeSha',v_tree_sha/);
  assert.doesNotMatch(safeReturn, /decrypted_secret|v_token|authorization|Bearer /i);
});

test("Memory Edge release transport has no variable repository, project or slug input", () => {
  assert.doesNotMatch(sql, /p_repo|p_project_ref|p_slug/);
  assert.match(sql, /pandora_memory_release_deploy_projectos_bridge_20260904\(p_commit_sha text\)/);
  assert.match(sql, /pandora_memory_release_deploy_projectos_bridge_v1\(p_commit_sha text\)/);
});
