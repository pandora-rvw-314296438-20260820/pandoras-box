"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const test=require("node:test");
const sql=fs.readFileSync("supabase/migrations/20260929150000_growth_experiment_evaluator_v1.sql","utf8");

test("growth evaluator is service-only and business-evidence only",()=>{
  assert.match(sql,/pandora_growth_evaluate_experiment_v1/);
  assert.match(sql,/session_user not in \('postgres','service_role','supabase_admin'\)/);
  assert.match(sql,/c\.is_test is false/);
  assert.match(sql,/e\.is_test is false/);
  assert.match(sql,/revoke all on function[\s\S]*from public,anon,authenticated/);
  assert.match(sql,/grant execute on function[\s\S]*to service_role/);
});

test("growth evaluator records terminal run plus exact receipts",()=>{
  assert.match(sql,/pandora_growth_experiment_runs/);
  assert.match(sql,/pandora_growth_experiment_receipts/);
  assert.match(sql,/'input_snapshot'/);
  assert.match(sql,/'terminal_result'/);
  assert.match(sql,/input_sha256/);
  assert.match(sql,/result_sha256/);
  assert.match(sql,/PANDORA_GROWTH_EXPERIMENT_IDEMPOTENCY_CONFLICT/);
});

test("inconclusive outcomes preserve the evidence gaps instead of inventing a winner",()=>{
  assert.match(sql,/v_status:='insufficient_evidence'/);
  assert.match(sql,/'winner',null/);
  assert.match(sql,/'causalClaim',false/);
  assert.match(sql,/'spendState',v_spend_state/);
  assert.match(sql,/when v_cost_rows=0 then 'missing'/);
  assert.match(sql,/'conversionDelayState',v_delay_state/);
  assert.match(sql,/'comparisonConditions',v_comparison/);
  assert.match(sql,/'uncertainty',v_uncertainty/);
  assert.match(sql,/'canonicalMemoryWritten',false/);
  assert.match(sql,/'spendAuthorized',false/);
});
