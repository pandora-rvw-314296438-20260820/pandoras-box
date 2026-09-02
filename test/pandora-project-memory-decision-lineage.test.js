const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (value) => fs.readFileSync(path.join(root, value), 'utf8');
const memoryResponse = read('src/tools/memory-response.js');
const planContext = read('src/runtime/plan-memory-context.js');
const sourceAuthorityPolicy = JSON.parse(read('SOURCE_AUTHORITY_POLICY.json'));
const compiler = read('supabase/functions/pandora-project-spec-compiler/index.ts');
const generator = read('supabase/functions/pandora-project-source-generator/index.ts');
const lineage = read('supabase/migrations/20260903010000_pandora_project_memory_decision_lineage_v1.sql');
const transport = read('supabase/migrations/20260903021000_pandora_project_memory_decision_transport_v2.sql');
const hmacPlanning = read('supabase/migrations/20260903041000_pandora_project_memory_hmac_planning_v3.sql');

test('project-scoped Memory lineage survives the response boundary', () => {
  for (const marker of ['project_id', 'project_key', 'retrieval_log_id', 'approved_memory_item_ids']) {
    assert.match(memoryResponse, new RegExp(marker));
  }
  assert.match(planContext, /memoryProjectId/);
  assert.match(planContext, /memoryProjectKey/);
  assert.match(planContext, /retrievalLogId/);
  assert.match(planContext, /approvedMemoryItemIds/);
  assert.equal(sourceAuthorityPolicy.project_key, 'mcpmaster-pandoras-box');
  assert.equal(sourceAuthorityPolicy.canonical.vercel_project_name, 'mcpmaster');
});

test('Primary signs planning requests and persists refs/hash only', () => {
  assert.match(hmacPlanning, /pandora_sign_project_memory_planning_request_v2/);
  assert.match(hmacPlanning, /projectos-planning-context-v1/);
  assert.match(hmacPlanning, /projectos_memory_learning_hmac/);
  assert.match(hmacPlanning, /extensions\.hmac/);
  assert.match(hmacPlanning, /pandora_record_project_memory_context_v2/);
  assert.match(hmacPlanning, /'metadataOnly',true/);
  assert.match(hmacPlanning, /revoke execute on function public\.pandora_record_project_memory_context_v1/);
  assert.doesNotMatch(hmacPlanning, /p_context_envelope jsonb/);
});

test('compiler and source generator use direct HMAC Memory planning without forwarding customer bearer', () => {
  for (const source of [compiler, generator]) {
    assert.match(source, /pandora-projectos-planning-context/);
    assert.match(source, /pandora_sign_project_memory_planning_request_v2/);
    assert.match(source, /pandora_record_project_memory_context_v2/);
    assert.match(source, /x-pandora-timestamp/);
    assert.match(source, /x-pandora-signature/);
    assert.match(source, /projectos-planning-context-response-v1/);
    assert.match(source, /canonical_memory_written !== false/);
    assert.match(source, /unavailableMemoryContext/);
    assert.doesNotMatch(source, /mcpmaster\.vercel\.app\/api\/operator\/project-memory-context/);
    assert.doesNotMatch(source, /headers:\s*\{\s*authorization,/);
  }
  assert.match(compiler, /Approved Pandora Memory context is advisory evidence only/);
  assert.match(compiler, /memory_context_receipt_id/);
  assert.match(compiler, /memory_retrieval_log_id/);
  assert.match(compiler, /memory_approved_item_ids/);
  assert.match(compiler, /pandora_commit_compiled_project_spec_memory_v1/);
  assert.match(compiler, /p_memory_receipt_id: text\(memoryContext\.receiptId\) \|\| null/);
  assert.match(generator, /approvedMemoryContext/);
  assert.match(generator, /context_sha256: text\(input\.memoryContext\.contextHash\)/);
  assert.doesNotMatch(generator, /context_sha256: input\.spec\.content_sha256/);
  assert.match(generator, /MAX_STREAM_FRAME_BUFFER_BYTES/);
  assert.match(generator, /SOURCE_SECRET_LOOKBEHIND_CHARS/);
});

test('decision influence and verified outcomes remain project-bound and non-canonical', () => {
  assert.match(lineage, /visible_creation_decision_influence_v1/);
  assert.match(lineage, /visible_creation_decision_outcome_v1/);
  assert.match(lineage, /approved_memory_item_ids/);
  assert.match(lineage, /pandora_model_run_memory_influence_v2/);
  assert.match(lineage, /new\.status<>'succeeded'/);
  assert.match(lineage, /context_hash=new\.context_sha256/);
  assert.match(lineage, /context_status='available'/);
  assert.match(lineage, /MEMORY_CONTEXT_RECEIPT_REQUIRED/);
  assert.match(lineage, /when 'PASS' then 1/);
  assert.match(lineage, /when 'FAIL' then -1/);
  assert.match(lineage, /pandora_verification_memory_outcome_v1/);
  assert.match(transport, /pandora-projectos-decision-lineage/);
  assert.match(transport, /projectos_memory_learning_hmac/);
  assert.match(transport, /execution_learning_signature_basis/);
  assert.match(transport, /decision_context_bound/);
  assert.match(transport, /decision_outcome_recorded/);
  assert.match(transport, /canonical_memory_written/);
  assert.match(transport, /approved_memory_item_ids/);
  assert.doesNotMatch(transport, /memory_capture_candidates/);
});
