'use strict';
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const edge=fs.readFileSync(path.join(root,'supabase/functions/pandora-intelligence-chat/index.ts'),'utf8');
const config=fs.readFileSync(path.join(root,'supabase/migrations/20260902040000_chat_c_kimi_runtime_provider_config_v1.sql'),'utf8');
const routing=fs.readFileSync(path.join(root,'supabase/migrations/20260902043000_chat_c_edge_runtime_convergence_v1.sql'),'utf8');
const must=(text,needle)=>assert.ok(text.includes(needle),`missing contract marker: ${needle}`);
const mustNot=(text,needle)=>assert.equal(text.includes(needle),false,`forbidden contract marker: ${needle}`);

test('Ask Pandora wires Kimi only through trusted service RPC and preserves Gemini',()=>{
  must(edge,'pandora_kimi_chat_request_v1');
  must(edge,'pandora_worker_b_gemini_request_20260829');
  must(edge,'pandora_runtime_provider_configs');
  for(const forbidden of ['api.moonshot.ai','moonshot_api_key','kimi_api_key'])mustNot(edge,forbidden);
  must(edge,'stream:false');
  must(edge,'req.signal.aborted');
  must(edge,'REQUEST_CANCELLED');
  must(routing,"('kimi','stream_mode','buffered_v1'");
});

test('provider choice is server-owned and Kimi defaults fail closed',()=>{
  mustNot(edge,'b.provider');
  mustNot(edge,'b.model');
  must(edge,'preferred_tasks');
  must(edge,'cfg.enabled&&cfg.routingEligible');
  must(config,"('kimi','enabled','false',true,now())");
  must(config,"('kimi','default_model','kimi-k3',true,now())");
});

test('fallback and sticky recovery are bounded explicit and classified',()=>{
  must(edge,'["provider_unavailable","timeout","rate_limited"]');
  must(edge,'pandora_read_intelligence_thread_route_v1');
  must(edge,'pandora_claim_intelligence_thread_route_v1');
  must(edge,'pandora_recover_intelligence_thread_route_v1');
  must(edge,'recoveryEpoch');
  must(edge,'fallbackUsed');
  must(edge,'.slice(0,4)');
  must(edge,'crossProviderEligible:true');
  must(edge,'crossProviderEligible:false');
  must(edge,'crossesProvider&&rec(e).crossProviderEligible!==true');
});

test('routing state wrappers remain service-role only',()=>{
  for(const fn of ['pandora_read_intelligence_thread_route_v1','pandora_claim_intelligence_thread_route_v1','pandora_recover_intelligence_thread_route_v1']){
    must(routing,`revoke all on function public.${fn}`);
    const grant=routing.split('\n').find(line=>line.includes(`grant execute on function public.${fn}`));
    assert.ok(grant&&grant.includes('to service_role;'));
  }
});

test('Kimi and Gemini share owner trust gates and customer response stays provider-blind',()=>{
  must(edge,'auth.getUser()');
  must(edge,'memberships');
  must(edge,'["owner","admin"]');
  must(edge,'consume_runtime_rate_limit');
  must(edge,'provider:result.provider,model:result.model');
  const start=edge.indexOf('return res({ok:true,threadId:tid');
  const end=edge.indexOf('}catch(e)',start);
  assert.ok(start>=0&&end>start);
  const publicSuccess=edge.slice(start,end);
  mustNot(publicSuccess,'provider:result');
  mustNot(publicSuccess,'model:result');
});
