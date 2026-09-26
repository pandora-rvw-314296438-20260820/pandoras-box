"use strict";
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const script=fs.readFileSync(path.join(root,'scripts/verify-operations-memory-production.mjs'),'utf8');
const build=fs.readFileSync(path.join(root,'scripts/build-vercel-pandora-web.sh'),'utf8');
const vercel=JSON.parse(fs.readFileSync(path.join(root,'vercel.json'),'utf8'));

test('production build preserves canonical Vercel command and executes the real workload Memory canary inside it',()=>{
  assert.equal(vercel.buildCommand,'npm run build && bash scripts/build-vercel-pandora-web.sh');
  assert.match(build,/node scripts\/verify-operations-memory-production\.mjs/);
  assert.match(script,/getVercelOidcToken/);
  assert.match(script,/getTaskContext/);
  assert.match(script,/getPerformance/);
  assert.match(script,/proposeOutcome/);
  assert.match(script,/reconcileOutcome/);
  assert.match(script,/canonicalMemoryWritten!==false/);
});
test('canary keeps uncertain commercial metadata unknown and only publishes sanitized proof',()=>{
  assert.match(script,/modelRevision:null/);
  assert.match(script,/estimatedCostMicros:null/);
  assert.match(script,/billedCostMicros:null/);
  assert.match(script,/inputTokens:null,outputTokens:null,totalTokens:null/);
  assert.match(script,/operations-memory-canary\.json/);
  assert.doesNotMatch(script,/proof\s*=\s*\{[^}]*token/s);
});
test('live native cron and exact-head repair migrations are source tracked',()=>{
  const cron=fs.readFileSync(path.join(root,'supabase/migrations/20260926061518_operations_native_pg_cron_worker_v1.sql'),'utf8');
  const fix=fs.readFileSync(path.join(root,'supabase/migrations/20260926062157_operations_native_exact_head_binding_fix_v1.sql'),'utf8');
  assert.match(cron,/pandora_ops_native_cron_tick_v1/);
  assert.match(cron,/pandora_ops_enable_native_cron_worker_v1/);
  assert.match(fix,/OPS_NATIVE_CRON_SOURCE_FIX_BASE_MISMATCH/);
  assert.match(fix,/v_head is distinct from t\.head_sha/);
});
