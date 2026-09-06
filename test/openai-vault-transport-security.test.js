'use strict';
const fs=require('node:fs');
const path=require('node:path');
const test=require('node:test');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20260906154900_openai_provider_failover_v3.sql'),'utf8');

test('OpenAI transport is fixed-host Vault-backed and service-role only',()=>{
  assert.match(migration,/where name='openai_key'/);
  assert.match(migration,/https:\/\/api\.openai\.com\/v1\/chat\/completions/);
  assert.match(migration,/revoke all on function public\.pandora_openai_chat_request_v1\(text,jsonb\) from public,anon,authenticated/);
  assert.match(migration,/grant execute on function public\.pandora_openai_chat_request_v1\(text,jsonb\) to service_role/);
  assert.doesNotMatch(migration,/return\s+v_key/i);
  assert.match(migration,/provider response failed secret-leak guard/);
});

test('OpenAI transport is bounded and classifies quota separately from rate limits',()=>{
  assert.match(migration,/v_max_request_bytes constant integer := 1048576/);
  assert.match(migration,/v_max_response_bytes constant integer := 2097152/);
  assert.match(migration,/v_max_output_tokens constant integer := 16384/);
  assert.match(migration,/v_max_attempts constant integer := 2/);
  assert.match(migration,/insufficient_quota/);
  assert.match(migration,/quota_exhausted/);
  assert.match(migration,/rate_limit/);
  assert.match(migration,/statement_timeout='90s'/);
});

test('OpenAI provider is enabled only through server-owned runtime config',()=>{
  assert.match(migration,/\('openai','enabled','true',true,now\(\)\)/);
  assert.match(migration,/\('openai','routing_eligible','true',true,now\(\)\)/);
  assert.match(migration,/\('openai','fallback_enabled','true',true,now\(\)\)/);
  assert.match(migration,/\('openai','default_model','gpt-5\.6-terra',true,now\(\)\)/);
  assert.match(migration,/provider-auto-failover-v3/);
});
