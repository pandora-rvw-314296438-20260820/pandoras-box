"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const sql=fs.readFileSync("supabase/migrations/20260927105500_operations_chatgpt_direct_ingress_v1.sql","utf8");

test("ChatGPT direct ingress skips specialist inference by default",()=>{
  assert.match(sql,/reasoningOrigin','chatgpt_connected_session/);
  assert.match(sql,/specialistReasoningInvoked',false/);
  assert.match(sql,/modelIdentityAsserted',false/);
  assert.match(sql,/inference_cost_micros','0'/);
  assert.doesNotMatch(sql,/pandora_ops_inference_transition_v1\(/);
});

test("direct ingress is management-plane only and has no public route",()=>{
  assert.match(sql,/private\.pandora_ops_chatgpt_direct_submit_v1/);
  assert.match(sql,/revoke all on function private\.pandora_ops_chatgpt_direct_submit_v1/);
  assert.match(sql,/public,anon,authenticated,service_role/);
  assert.match(sql,/supabase_management_private_rpc/);
});

test("source authority is server-read canonical main, never caller supplied",()=>{
  assert.match(sql,/git\/ref\/heads\/main/);
  assert.match(sql,/v_source_sha:=v_main#>>'\{body,object,sha\}'/);
  assert.match(sql,/repository','pandora-rvw-314296438-20260820\/pandoras-box'/);
  assert.doesNotMatch(sql,/p_source_sha/);
});

test("ChatGPT direct parent and RDP child are zero-cost read-only Operations tasks",()=>{
  assert.match(sql,/OPS-CHATGPT-DIRECT-/);
  assert.match(sql,/OPS-RDP-DIRECT-/);
  assert.match(sql,/'maxCostMicros',0/);
  assert.match(sql,/'risk','read'/);
  assert.match(sql,/chatgpt\.reasoned/);
  assert.match(sql,/rdp\.delegate/);
  assert.match(sql,/rdp\.execute/);
});

test("execution profile remains a fixed whitelist rather than commands",()=>{
  for(const profile of [
    "toolchain_verify","github_runner_verify","android_verify",
    "flutter_verify","repo_test","repo_build"
  ]) assert.match(sql,new RegExp(profile.replace(".","\\.")));
  assert.match(sql,/OPS_CHATGPT_DIRECT_PROFILE_INVALID/);
  assert.match(sql,/powershell\|cmd\\\.exe\|bash\|curl\|wget/);
});

test("RDP child must pass independent canonical verification before parent completes",()=>{
  assert.match(sql,/pandora_ops_record_verification_v1/);
  assert.match(sql,/pandora_ops_verify_v1/);
  assert.match(sql,/child\.builder_worker_key<>'pandora-rdp-windows-01'/);
  assert.match(sql,/proof->>'proofSha256'/);
  assert.match(sql,/parent\.status='implementing'/);
  assert.match(sql,/parent_handed_off/);
});

test("verified completion queues review-gated Pandora Memory learning",()=>{
  assert.match(sql,/pandora_verified_learning_outbox/);
  assert.match(sql,/learning_kind/);
  assert.match(sql,/'outcome'/);
  assert.match(sql,/review-gated learning candidate and not self-promoted Memory/);
  assert.match(sql,/verified_learning_queued/);
});

test("minute tick advances execution without requiring another model",()=>{
  assert.match(sql,/pandora-operations-chatgpt-direct-v1/);
  assert.match(sql,/'\* \* \* \* \*'/);
  assert.match(sql,/pandora_ops_chatgpt_direct_tick_v1/);
  assert.doesNotMatch(sql,/gemini_rpc/);
  assert.doesNotMatch(sql,/bedrock_converse/);
});
