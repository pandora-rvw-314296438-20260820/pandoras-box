"use strict";
const fs=require("node:fs");
const test=require("node:test");
const assert=require("node:assert/strict");
const route=fs.readFileSync("api/operations-native-worker.ts","utf8");
const migration=fs.readFileSync("supabase/migrations/20261002102000_pandora_lane_f_bedrock_live_catalog_v2.sql","utf8");
const local=fs.readFileSync("apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart","utf8");

test("Bedrock sync uses only Vercel workload identity plus the dedicated role",()=>{
  assert.match(route,/resolveVercelWorkloadToken/);
  assert.match(route,/assumeRoleWithVercelOidc/);
  assert.doesNotMatch(route,/AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|Github_supabase|SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(route,/signedAction === "bedrock_catalog_sync"/);
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

test("owner-approved probe cycle cannot silently become recurring spend",()=>{
  assert.doesNotMatch(migration,/cron\.schedule|enable_schedule/i);
});

test("Bedrock sync reuses the existing Vercel function budget",()=>{
  assert.match(route,/export default async function operationsNativeWorker/);
  assert.doesNotMatch(route,/\/api\/bedrock-model-catalog-sync/);
});

test("Bedrock catalog mutations stay behind the existing Vercel-OIDC control bridge",()=>{
  const control=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts","utf8");
  for(const action of ["bedrock_catalog_sync_claim","bedrock_catalog_sync_apply","bedrock_catalog_sync_fail"]) assert.match(control,new RegExp(action));
  assert.match(migration,/ORGANIZATION_SCOPE_DENIED/);
});
