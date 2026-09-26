"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.join(__dirname,"..");
const worker=fs.readFileSync(path.join(root,"api/operations-native-worker.ts"),"utf8");
const vercel=JSON.parse(fs.readFileSync(path.join(root,"vercel.json"),"utf8"));
const migration=fs.readFileSync(path.join(root,"supabase/migrations/20260926044500_operations_vercel_cron_wake_v1.sql"),"utf8");

test("wake supports daily Vercel cron, signed Supabase wake, and manual digest authorization",()=>{
  assert.match(worker,/request\.method === "GET"/);
  assert.match(worker,/request\.method === "POST"/);
  assert.match(worker,/process\.env\.CRON_SECRET/);
  assert.match(worker,/timingSafeEqual/);
  assert.match(worker,/operations_wake_authorize/);
  assert.match(worker,/PANDORA_OPS_WAKE_HMAC_SECRET/);
  assert.match(worker,/createHmac/);
  assert.match(worker,/operations_wake_nonce_consume/);
  assert.match(worker,/if \(manualWake\)/);
  assert.doesNotMatch(worker,/CRON_SECRET\s*=\s*["'][^"']+/);
});
test("cron route is fixed and has no arbitrary scope or query input",()=>{
  assert.deepEqual(vercel.crons,[{path:"/api/operations-native-worker",schedule:"0 0 * * *"}]);
  assert.match(worker,/if \(url\.search \|\| url\.hash\)/);
  assert.match(worker,/OPERATIONS_PROJECT_ID|CANARY_TASK/);
});
test("provisioner creates sensitive wake secrets server-side and never returns them",()=>{
  assert.match(migration,/gen_random_bytes\(48\)/);
  assert.match(migration,/\/v10\/projects\/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk\/env\?upsert=true/);
  assert.match(migration,/'key','CRON_SECRET'/);
  assert.match(migration,/'key','PANDORA_OPS_WAKE_HMAC_SECRET'/);
  assert.match(migration,/'type','sensitive'/);
  assert.match(migration,/'target',jsonb_build_array\('production'\)/);
  assert.match(migration,/'secretReturned',false/);
  assert.match(migration,/v_cron_secret:=null; v_hmac_secret:=null/);
  assert.doesNotMatch(migration,/return\s+v_(cron|hmac)_secret/i);
});
test("Supabase minute scheduler emits only HMAC proof and consumes nonces before work",()=>{
  assert.match(migration,/create or replace function private\.pandora_ops_emit_vercel_wake_v1/);
  assert.match(migration,/extensions\.hmac/);
  assert.match(migration,/x-pandora-wake-signature/);
  assert.doesNotMatch(migration,/authorization','Bearer '\|\|v_(cron|hmac)_secret/);
  assert.match(migration,/cron\.schedule\('pandora-operations-native-wake-v1','\* \* \* \* \*'/);
  assert.match(migration,/create table private\.pandora_ops_wake_nonces/);
  assert.match(migration,/pandora_ops_wake_nonce_consume_v1/);
  assert.match(worker,/OPS_NATIVE_WAKE_REPLAY_DENIED/);
});

test("native release verification is Operations-native and ProjectOS-free",()=>{
  const control=fs.readFileSync(path.join(root,"supabase/functions/mcpmaster-supabase-control/index.ts"),"utf8");
  const verify=fs.readFileSync(path.join(root,"supabase/migrations/20260926045200_operations_native_verification_v1.sql"),"utf8");
  assert.match(verify,/create table private\.pandora_ops_verification_receipts/);
  assert.match(verify,/references private\.pandora_ops_workspaces/);
  assert.match(verify,/create or replace function public\.pandora_ops_native_release_verify_v1/);
  assert.match(verify,/OPS-CLOUD-CONNECTORS-RELEASE-V1/);
  assert.match(verify,/pulls\/741/);
  assert.match(verify,/Pandora coordinator \/ integration/);
  assert.match(verify,/connector-contract/);
  assert.match(verify,/20260926012832/);
  assert.match(verify,/select \* into ov from private\.pandora_ops_verification_receipts/);
  assert.match(verify,/select \* into legacy from public\.pandora_verification_runs/);
  assert.doesNotMatch(verify,/insert into public\.pandora_project_specs|insert into public\.pandora_project_versions/);
  assert.match(control,/operations_native_release_verify/);
  assert.match(control,/pandora_ops_native_release_verify_v1/);
  assert.match(worker,/operations_native_release_verify/);
  assert.match(worker,/OPS_NATIVE_RELEASE_VERIFICATION_UNCONFIRMED/);
});

test("control bridge exposes only fixed nonce consumption",()=>{
  const control=fs.readFileSync(path.join(root,"supabase/functions/mcpmaster-supabase-control/index.ts"),"utf8");
  assert.match(control,/operations_wake_nonce_consume/);
  assert.match(control,/pandora_ops_wake_nonce_consume_v1/);
  assert.match(control,/p_project_id: OPERATIONS_PROJECT_ID/);
});

test("native wake proves Vercel workload identity against the Operations-only Memory endpoint",()=>{
  assert.match(worker,/MEMORY_URL = "https:\/\/ivmvufhcsezyhczzondn\.supabase\.co\/functions\/v1\/pandora-memory-bridge"/);
  assert.match(worker,/x-pandora-vercel-oidc/);
  assert.match(worker,/operation: "context"/);
  assert.match(worker,/authorizationGranted !== false/);
  assert.match(worker,/memoryProjectRef !== "ivmvufhcsezyhczzondn"/);
  assert.doesNotMatch(worker,/memory\.context|payload\.data\.context/);
});
