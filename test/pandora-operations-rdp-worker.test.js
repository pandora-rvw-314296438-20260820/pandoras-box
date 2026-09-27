"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const migration=fs.readFileSync("supabase/migrations/20260927050137_operations_rdp_worker_v1.sql","utf8");
const routes=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/rdp-routes.mjs","utf8");
const control=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts","utf8");
const endpoint=fs.readFileSync("api/operations-rdp-worker.ts","utf8");
const worker=fs.readFileSync("scripts/operations/rdp-worker.ps1","utf8");

test("RDP worker is a distinct least-privilege Operations identity",()=>{
  assert.match(migration,/engine=\x27rdp\x27/);
  assert.match(migration,/pandora-rdp-windows-01/);
  assert.match(migration,/rdp:EC2AMAZ-SPAE2VG:operations-worker-v1/);
  assert.match(migration,/pandora_operations_rdp_worker_token_sha256/);
  const spec=routes.slice(routes.indexOf("const WORKER"),routes.indexOf("const TASK_PATTERN"));
  assert.doesNotMatch(spec,/source\.write|runtime\.deploy|release\.verify|memory\.integrate/);
});

test("RDP routes are isolated but reuse Operations claim and handoff",()=>{
  assert.match(control,/routeForRdpOperations/);
  assert.match(routes,/pandora_ops_claim_v1/);
  assert.match(routes,/pandora_ops_dispatch_v1/);
  assert.match(routes,/pandora_ops_handoff_v1/);
  assert.match(routes,/^const TASK_PATTERN = \/\^OPS-RDP-/m);
});

test("RDP transport is signed and replay fenced",()=>{
  assert.match(endpoint,/createHmac\("sha256", token\)/);
  assert.match(endpoint,/operations_rdp_authorize/);
  assert.match(endpoint,/operations_wake_nonce_consume/);
  assert.match(endpoint,/RDP_WORKER_REPLAY_REJECTED/);
  assert.match(worker,/x-pandora-signature/);
  assert.match(worker,/x-pandora-nonce/);
});

test("RDP worker only claims explicit read-risk RDP tasks",()=>{
  assert.match(endpoint,/task\?\.spec\?\.risk === "read"/);
  assert.match(endpoint,/capabilities\.includes\("rdp\.execute"\)/);
  assert.match(endpoint,/TASK_PATTERN\.test/);
});

test("RDP handoff source identity comes from scheduler task state, not worker evidence",()=>{
  assert.match(endpoint,/task\?\.spec\?\.source\?\.baseSha/);
  assert.match(endpoint,/RDP_WORKER_SOURCE_BINDING_INVALID/);
  assert.match(endpoint,/headSha: sourceSha/);
  assert.match(endpoint,/source:\$\{sourceSha\}/);
  assert.doesNotMatch(worker,/headSha\s*=/);
});

test("RDP executor is deterministic and has no source or release mutation commands",()=>{
  assert.match(worker,/Pandora GitHub Runner/);
  assert.match(worker,/flutter --version/);
  assert.match(worker,/adb devices -l/);
  assert.doesNotMatch(worker,/\bgit\s+(push|commit|merge|checkout)\b/i);
  assert.doesNotMatch(worker,/\bvercel\s+(deploy|promote|rollback)\b/i);
  assert.doesNotMatch(worker,/SUPABASE_SERVICE_ROLE_KEY|Github_supabase|ghp_|sk-proj/i);
});
