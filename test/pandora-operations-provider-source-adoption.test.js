import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const sql=fs.readFileSync("supabase/migrations/20260929121000_operations_provider_verified_source_adoption_v1.sql","utf8");

test("provider source adoption requires exact merged GitHub proof",()=>{
  assert.match(sql,/pulls\/.*p_pull_request/);
  assert.match(sql,/pr->'merged' is distinct from 'true'::jsonb/);
  assert.match(sql,/merge_commit->'parents'/);
  assert.match(sql,/check-runs\?per_page=100/);
  assert.match(sql,/Pandora coordinator \/ integration/);
  assert.match(sql,/compare\/.*p_merge_sha/);
});
test("provider source adoption cannot grant completion or production authority",()=>{
  assert.match(sql,/t\.spec->>'risk' is distinct from 'source'/);
  assert.match(sql,/set status='verifying'/);
  assert.doesNotMatch(sql,/set status='complete'/);
  assert.doesNotMatch(sql,/spend\.authorized|production_release/);
});
test("active leases and non-independent reconciler fail closed",()=>{
  assert.match(sql,/OPS_PROVIDER_SOURCE_ADOPTION_ACTIVE_LEASE/);
  assert.match(sql,/OPS_PROVIDER_SOURCE_ADOPTION_INDEPENDENT_RECONCILER_REQUIRED/);
  assert.match(sql,/pandora_ops_settle_v1/);
});
