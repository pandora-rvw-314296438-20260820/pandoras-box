"use strict";
const fs=require("node:fs");
const test=require("node:test");
const assert=require("node:assert/strict");
const route=fs.readFileSync("api/bedrock-model-catalog-sync.ts","utf8");
const migration=fs.readFileSync("supabase/migrations/20261002102000_pandora_lane_f_bedrock_live_catalog_v2.sql","utf8");
const local=fs.readFileSync("apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart","utf8");

test("Bedrock sync uses only Vercel workload identity plus the dedicated role",()=>{
  assert.match(route,/resolveVercelWorkloadToken/);
  assert.match(route,/assumeRoleWithVercelOidc/);
  assert.doesNotMatch(route,/AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|Github_supabase/);
});
test("runtime probe is exactly one minimal Converse call per conversational candidate",()=>{
  assert.match(route,/prompt: "OK"/);
  assert.match(route,/maxTokens: 1/);
  assert.match(route,/converseWithBedrockTarget/);
  assert.doesNotMatch(route,/retry|backoff/i);
});
test("catalog is fail-closed until bounded runtime verification passes",()=>{
  assert.match(migration,/availability_state='routable'/);
  assert.match(migration,/runtime_verification_status='passed'/);
  assert.match(migration,/lifecycle_status='ACTIVE'/);
  assert.match(migration,/'conversation'=any\(workflow_scopes\)/);
  assert.match(migration,/not_present_in_live_aws_catalog/);
});
test("phone local AI is an explicit opt-in and defaults OFF",()=>{
  assert.match(local,/bool usePhoneAi = false/);
  assert.match(local,/if \(!usePhoneAi\) return _record\(false, 'phone_ai_disabled'\)/);
});
