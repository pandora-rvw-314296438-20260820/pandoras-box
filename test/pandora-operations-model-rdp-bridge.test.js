"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const migration=fs.readFileSync("supabase/migrations/20260927093535_operations_model_rdp_bridge_v1.sql","utf8");
const hold=fs.readFileSync("supabase/migrations/20260927112500_operations_model_rdp_vercel_hobby_hold_v1.sql","utf8");
const consolidation=fs.readFileSync("supabase/migrations/20260928170000_operations_native_reasoning_rdp_consolidation_v1.sql","utf8");
const nativeWorker=fs.readFileSync("api/operations-native-worker.ts","utf8");
const reasoningFleet=fs.readFileSync("supabase/migrations/20260927070752_operations_reasoning_fleet_v1.sql","utf8");
const routes=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/reasoning-rdp-routes.mjs","utf8");
const control=fs.readFileSync("supabase/functions/mcpmaster-supabase-control/index.ts","utf8");
const rdp=fs.readFileSync("api/operations-rdp-worker.ts","utf8");
const worker=fs.readFileSync("scripts/operations/rdp-worker.ps1","utf8");

test("ordinary RDP automation tasks remain model-first while direct OPS-RDP canaries stay direct",()=>{
  assert.match(migration,/q\.task_key !~ '\^OPS-RDP-'/);
  assert.match(migration,/\(q\.spec->'requiredCapabilities'\) \? 'rdp\.execute'/);
  assert.match(migration,/q\.spec->>'risk'='read'/);
  assert.match(migration,/q\.spec->>'verificationProfile'='automation'/);
  assert.match(rdp,/\^OPS-RDP-/);
});

test("reasoning plan can choose only bounded profiles, never commands",()=>{
  assert.match(migration,/count\(\*\) from jsonb_object_keys\(plan\)\)<>2/);
  assert.match(migration,/plan \?& array\['profile','reason'\]/);
  assert.match(migration,/powershell\|cmd\\\.exe\|bash\|curl\|wget/);
  assert.match(migration,/allowed_profiles/);
  assert.match(migration,/OPS_REASONING_RDP_PLAN_INVALID/);
});

test("model-first bridge contract stays exact-source, budget fenced and provider routed",()=>{
  assert.match(migration,/OPS_REASONING_RDP_INFERENCE_BUDGET_REQUIRED/);
  assert.match(migration,/workspaceAvailableMicros/);
  assert.match(migration,/structured_extraction/);
  assert.match(migration,/no_fresh_approved_structured_extraction_model/);
  assert.match(migration,/sourceSha/);
});

test("child execution is independently verified before parent convergence",()=>{
  assert.match(migration,/pandora_ops_reasoning_rdp_verify_child_v1/);
  assert.match(migration,/pandora_ops_record_verification_v1/);
  assert.match(migration,/pandora_ops_verify_v1/);
  assert.match(migration,/child\.status<>'complete'/);
  assert.match(migration,/provider_billing_evidence_required/);
  assert.match(migration,/unknown_billing<>0/);
});

test("RDP repo profiles only run canonical main ancestry and never publish source",()=>{
  assert.match(worker,/merge-base --is-ancestor \$SourceSha FETCH_HEAD/);
  assert.match(worker,/checkout --detach \$SourceSha/);
  assert.match(worker,/npm\.cmd --prefix \$jobRoot test/);
  assert.match(worker,/npm\.cmd --prefix \$jobRoot run build/);
  assert.doesNotMatch(worker,/\bgit\s+push\b/i);
  assert.doesNotMatch(worker,/\bgit\s+commit\b/i);
  assert.doesNotMatch(worker,/\bvercel\s+(deploy|promote|rollback)\b/i);
});

test("model-first wake is consolidated into the existing native worker without adding a Vercel function",()=>{
  assert.equal(fs.existsSync("api/operations-reasoning-rdp-bridge.ts"),false);
  assert.match(hold,/cron\.unschedule/);
  assert.match(nativeWorker,/runReasoningRdpStep/);
  assert.match(nativeWorker,/operations_reasoning_rdp_candidate/);
  assert.match(nativeWorker,/operations_reasoning_rdp_materialize/);
  assert.match(consolidation,/operations_model_rdp_bridge','enabled','true'/);
  assert.match(consolidation,/wake_path','operations-native-worker-v1'/);
  assert.match(consolidation,/standalone_vercel_function','false'/);
});

test("control plane preserves dedicated model-first bridge identity for later consolidation",()=>{
  assert.match(control,/routeForReasoningRdpOperations/);
  assert.match(routes,/pandora-reasoning-rdp-bridge-v1/);
  assert.match(routes,/vercel:mcpmaster:reasoning-rdp-bridge-v1/);
  assert.match(routes,/pandora_ops_reasoning_rdp_materialize_v1/);
});

test("Gemini routes remain available while held Bedrock models stay in the catalog",()=>{
  assert.match(migration,/gemini-3\.5-flash-lite/);
  assert.match(migration,/gemini-3\.7-flash/);
  assert.match(migration,/gemini-3\.1-pro-preview/);
  assert.match(migration,/allowedProviders.*bedrock.*gemini/s);
  assert.match(migration,/maxCostMicros',1000000/);
});

test("Astra remains fail-closed and requires extra-high attested ChatGPT worker",()=>{
  assert.match(consolidation,/chatgpt_worker','required_thinking_effort','extra_high'/);
  assert.match(consolidation,/zero_workspace_budget_or_unattested_chatgpt_worker/);
  assert.match(reasoningFleet,/awaiting_live_model_attestation/);
  assert.match(reasoningFleet,/gpt-6-astra/);
});

test("RDP executor and ARTEMIS verifier remain separate and verified outcomes queue to Memory",()=>{
  assert.match(routes,/\["pandora", "rdp", "artemis", "01"\]\.join\("-"\)/);
  assert.match(routes,/pandora_ops_register_rdp_artemis_verifier_v1/);
  assert.match(routes,/pandora_ops_reasoning_rdp_queue_memory_v1/);
  assert.match(consolidation,/pandora_verified_learning_outbox/);
  assert.match(consolidation,/executorWorker','pandora-rdp-windows-01'/);
  assert.match(consolidation,/verifierWorker','pandora-rdp-artemis-01'/);
  assert.match(consolidation,/canonicalMemoryWritten',false/);
});
