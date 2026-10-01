"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const test=require("node:test");
const sql=fs.readFileSync("supabase/migrations/20260929143000_meta_zero_delivery_action_broker_v1.sql","utf8");

test("zero-delivery broker supports only PAUSE on controlled-test assets",()=>{
  assert.match(sql,/target_type in \('campaign','adset','ad'\)/);
  assert.match(sql,/action='pause'/);
  assert.match(sql,/payload = jsonb_build_object\('status','PAUSED'\)/);
  assert.match(sql,/metadata->>'purpose'='controlled-test'/);
  assert.match(sql,/business_kpi'.*false/s);
  assert.match(sql,/delivery_authorized'.*false/s);
  assert.doesNotMatch(sql,/daily_budget|lifetime_budget|budget_amount|DELETE.*graph\.facebook|\/campaigns'::varchar/i);
});

test("approvals are short-lived hash-bound and one-write only",()=>{
  assert.match(sql,/p_ttl_seconds not between 60 and 900/);
  assert.match(sql,/payload_sha256/);
  assert.match(sql,/max_provider_writes integer not null default 1/);
  assert.match(sql,/consumed_provider_writes>=v_approval\.max_provider_writes/);
  assert.match(sql,/for update/);
  assert.match(sql,/unique\(approval_id\)/);
  assert.match(sql,/unique\(organization_id,project_id,request_key\)/);
});

test("provider result is confirmed by readback and never relabelled mutation success",()=>{
  assert.match(sql,/fields=id,status,effective_status/);
  assert.match(sql,/desired_state_confirmed/);
  assert.match(sql,/mutation_success_claimed boolean not null default false/);
  assert.match(sql,/'mutationSuccessClaimed',false/);
  assert.match(sql,/'providerAccepted'/);
  assert.match(sql,/'incurredSpendReversible',false/);
});

test("kill switch blocks expansion and returns authorized pause targets",()=>{
  assert.match(sql,/pandora_meta_set_zero_delivery_kill_switch_v1/);
  assert.match(sql,/'newNonPauseActionsAllowed',false/);
  assert.match(sql,/'authorizedPauseTargets'/);
  assert.match(sql,/'spendAuthorized',false/);
});

test("client roles cannot execute broker tables or RPCs",()=>{
  assert.match(sql,/revoke all on private\.pandora_meta_zero_delivery_action_approvals from public,anon,authenticated,service_role/);
  assert.match(sql,/revoke all on function public\.pandora_meta_execute_zero_delivery_action_v1[\s\S]*from public,anon,authenticated/);
  assert.match(sql,/session_user not in \('postgres','service_role','supabase_admin'\)/);
});
