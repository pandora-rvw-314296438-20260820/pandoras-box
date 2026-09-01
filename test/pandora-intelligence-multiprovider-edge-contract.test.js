'use strict';
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const edge=fs.readFileSync(path.join(root,'supabase/functions/pandora-intelligence-chat/index.ts'),'utf8');
const config=fs.readFileSync(path.join(root,'supabase/migrations/20260902040000_chat_c_kimi_runtime_provider_config_v1.sql'),'utf8');
const routing=fs.readFileSync(path.join(root,'supabase/migrations/20260902043000_chat_c_edge_runtime_convergence_v1.sql'),'utf8');

test('Ask Pandora wires Kimi only through the trusted service RPC and preserves Gemini',()=>{
  assert.match(edge,/pandora_kimi_chat_request_v1/);
  assert.match(edge,/pandora_worker_b_gemini_request_20260829/);
  assert.match(edge,/pandora_runtime_provider_configs/);
  assert.doesNotMatch(edge,/api\.moonshot\.ai|moonshot_api_key|kimi_api_key/i);
  assert.match(edge,/stream:false/);
  assert.match(edge,/req\\.signal\\.aborted/);
  assert.match(edge,/REQUEST_CANCELLED/);
  assert.match(routing,/\('kimi','stream_mode','buffered_v1'/);
});

test('provider choice is server-owned and Kimi defaults fail closed',()=>{
  assert.doesNotMatch(edge,/\bb\.provider\b|\bb\.model\b/);
  assert.match(edge,/preferred_tasks/);
  assert.match(edge,/cfg\.enabled&&cfg\.routingEligible/);
  assert.match(config,/\('kimi','enabled','false',true,now\(\)\)/);
  assert.match(config,/\('kimi','default_model','kimi-k3',true,now\(\)\)/);
});

test('fallback and sticky recovery are bounded and explicit',()=>{
  assert.match(edge,/\["provider_unavailable","timeout","rate_limited"\]/);
  assert.match(edge,/pandora_read_intelligence_thread_route_v1/);
  assert.match(edge,/pandora_claim_intelligence_thread_route_v1/);
  assert.match(edge,/pandora_recover_intelligence_thread_route_v1/);
  assert.match(edge,/recoveryEpoch/);
  assert.match(edge,/fallbackUsed/);
});

test('routing state wrappers remain service-role only',()=>{
  for(const fn of ['pandora_read_intelligence_thread_route_v1','pandora_claim_intelligence_thread_route_v1','pandora_recover_intelligence_thread_route_v1']){
    assert.match(routing,new RegExp(`revoke all on function public\\.${fn}`));
    assert.match(routing,new RegExp(`grant execute on function public\\.${fn}[^;]+service_role`));
  }
});

test('Kimi and Gemini share the existing owner trust gates and customer response stays provider-blind',()=>{
  assert.match(edge,/auth\.getUser\(\)/);
  assert.match(edge,/memberships/);
  assert.match(edge,/\["owner","admin"\]/);
  assert.match(edge,/consume_runtime_rate_limit/);
  assert.match(edge,/provider:result\.provider,model:result\.model/);
  const successReturn=edge.match(/return res\(\{ok:true,threadId:tid[\s\S]*?\}\)\}catch/);
  assert.ok(successReturn);
  assert.doesNotMatch(successReturn[0],/provider:result|model:result/);
});
