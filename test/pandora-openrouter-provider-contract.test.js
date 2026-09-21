'use strict';
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const edge=fs.readFileSync(path.join(root,'supabase/functions/pandora-intelligence-chat/index.ts'),'utf8');
const rollout=fs.readFileSync(path.join(root,'supabase/migrations/20260921121500_openrouter_provider_failover_v4.sql'),'utf8');

test('OpenRouter remains a Vault-backed server-side fallback',()=>{
  assert.match(edge,/pandora_openrouter_chat_request_v1/);
  assert.match(edge,/provider==="openrouter"/);
  assert.match(edge,/openrouterConfig\(c\.admin\)/);
  assert.doesNotMatch(edge,/https:\/\/openrouter\.ai/);
  assert.doesNotMatch(edge,/where name=['"]openrouter['"]/);
  assert.match(rollout,/where name='openrouter'/);
  assert.match(rollout,/https:\/\/openrouter\.ai\/api\/v1\/chat\/completions/);
  assert.match(rollout,/grant execute on function public\.pandora_openrouter_chat_request_v1\(text,jsonb\) to service_role/);
  assert.match(rollout,/\('openrouter','fallback_enabled','true',true,now\(\)\)/);
  assert.match(rollout,/\('openrouter','default_model','qwen\/qwen3-30b-a3b-instruct-2507',true,now\(\)\)/);
});

test('OpenRouter billing and availability failures stay eligible for safe cross-provider recovery',()=>{
  assert.match(rollout,/p_status = 402[\s\S]*quota_exhausted/);
  assert.match(edge,/quota_exhausted/);
  assert.match(edge,/crossProviderEligible/);
  assert.match(edge,/\.slice\(0,6\)/);
  assert.match(edge,/provider-auto-failover-v4/);
});
