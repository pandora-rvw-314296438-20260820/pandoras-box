"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.join(__dirname,"..");
const worker=fs.readFileSync(path.join(root,"api/operations-native-worker.ts"),"utf8");
const control=fs.readFileSync(path.join(root,"supabase/functions/mcpmaster-supabase-control/index.ts"),"utf8");
const wake=fs.readFileSync(path.join(root,"supabase/migrations/20260926055500_operations_signed_wake_v1.sql"),"utf8");
const verify=fs.readFileSync(path.join(root,"supabase/migrations/20260926055600_operations_native_verification_v1.sql"),"utf8");

test("signed wake authenticates without exporting the Vault wake seed",()=>{
 assert.match(worker,/PANDORA_OPS_WAKE_HMAC_SECRET/);
 assert.match(worker,/createHmac/);
 assert.match(worker,/operations_wake_nonce_consume/);
 assert.match(worker,/operations_wake_authorize/);
 assert.match(worker,/OPS_NATIVE_WAKE_REPLAY_DENIED/);
 assert.doesNotMatch(wake,/vault\.create_secret/);
 assert.match(wake,/concat\('pandora_ops_','wake_token_v1'\)/);
 assert.match(wake,/extensions\.hmac/);
 assert.match(wake,/x-pandora-wake-signature/);
 assert.doesNotMatch(wake,/authorization','Bearer '\|\|v_seed/);
});
test("derived Vercel HMAC secret is provisioned server-to-server and never returned",()=>{
 assert.match(wake,/\/v10\/projects\/prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk\/env\?upsert=true/);
 assert.match(wake,/concat\('PANDORA_OPS_WAKE_HMAC_','SECRET'\)/);
 assert.match(wake,/'type','sensitive'/);
 assert.match(wake,/'secretReturned',false/);
 assert.match(wake,/v_derived:=null/);
 assert.doesNotMatch(wake,/return\s+v_(seed|derived|provider_token)/i);
});
test("wake replay is consumed once and scheduler cadence is fixed",()=>{
 assert.match(wake,/create table private\.pandora_ops_wake_nonces/);
 assert.match(wake,/on conflict do nothing/);
 assert.match(wake,/cron\.schedule\(/);
 assert.match(wake,/'\* \* \* \* \*'/);
 assert.match(wake,/https:\/\/mcpmaster\.vercel\.app\/api\/operations-native-worker/);
});
test("native release verification is independent and provider-bound",()=>{
 assert.match(verify,/private\.pandora_ops_verification_receipts/);
 assert.match(verify,/pandora_ops_native_release_verify_v1/);
 assert.match(verify,/pulls\/741/);
 assert.match(verify,/Pandora coordinator \/ integration/);
 assert.match(verify,/connector-contract/);
 assert.match(verify,/20260926012832/);
 assert.doesNotMatch(verify,/insert into public\.pandora_project_specs|insert into public\.pandora_project_versions/);
 assert.match(control,/operations_native_release_verify/);
 assert.match(worker,/operations_native_release_verify/);
});
test("control adapter keeps signed wake and verifier scope fixed",()=>{
 assert.match(control,/operations_wake_nonce_consume/);
 assert.match(control,/pandora_ops_wake_nonce_consume_v1/);
 assert.match(control,/taskId !== "OPS-CLOUD-CONNECTORS-RELEASE-V1"/);
 assert.match(control,/p_project_id: OPERATIONS_PROJECT_ID/);
});
