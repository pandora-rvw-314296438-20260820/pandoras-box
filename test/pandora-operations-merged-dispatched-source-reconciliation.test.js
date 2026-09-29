"use strict";
const fs=require("node:fs");
const test=require("node:test");
const assert=require("node:assert/strict");
const m=fs.readFileSync("supabase/migrations/20260929115500_operations_merged_dispatched_source_reconciliation_v1.sql","utf8");

test("expired dispatched source reconciliation is provider-verified and independent",()=>{
  assert.match(m,/v_lease\.state not in \('running','reconcile'\)/);
  assert.match(m,/v_lease\.expires_at>clock_timestamp\(\)/);
  assert.match(m,/v_pr->>'merged' is distinct from 'true'/);
  assert.match(m,/check-runs\?per_page=100/);
  assert.match(m,/not in \('success','neutral','skipped'\)/);
  assert.match(m,/v_worker\.worker_key is not distinct from v_task\.builder_worker_key/);
  assert.match(m,/private\.pandora_ops_settle_v1/);
  assert.match(m,/status='handed_off'/);
});

test("reconciler cannot widen source or production authority",()=>{
  assert.match(m,/v_task\.spec->>'risk'<>'source'/);
  assert.match(m,/v_task\.spec#>>'\{source,repository\}' is distinct from p_repository/);
  assert.match(m,/merge_commit_sha/);
  assert.match(m,/currentMainSha/);
  assert.doesNotMatch(m,/spend\.authorized|provider\/meta\/actions|update private\.pandora_ops_tasks set status='complete'/);
});
