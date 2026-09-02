const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (value) => fs.readFileSync(path.join(root, value), 'utf8');
const memoryResponse = read('src/tools/memory-response.js');
const planContext = read('src/runtime/plan-memory-context.js');
const sourceAuthority = read('src/runtime/source-authority.js');
const provider = read('src/projectos/project-memory-context-provider.js');
const operator = read('apps/meta-business-mcp/src/operator/api.js');
const compiler = read('supabase/functions/pandora-project-spec-compiler/index.ts');
const generator = read('supabase/functions/pandora-project-source-generator/index.ts');
const lineage = read('supabase/migrations/20260903010000_pandora_project_memory_decision_lineage_v1.sql');
const transport = read('supabase/migrations/20260903021000_pandora_project_memory_decision_transport_v2.sql');

test('project-scoped Memory lineage survives the response boundary', () => {
  for (const marker of ['project_id', 'project_key', 'retrieval_log_id', 'approved_memory_item_ids']) {
    assert.match(memoryResponse, new RegExp(marker));
  }
  assert.match(planContext, /memoryProjectId/);
  assert.match(planContext, /memoryProjectKey/);
  assert.match(planContext, /retrievalLogId/);
  assert.match(planContext, /approvedMemoryItemIds/);
  assert.match(planContext, /slice\(0, 50\)/);
});

test('operator records an immutable exact-project context receipt before decisions', () => {
  assert.match(provider, /visible_creation\.\$\{decisionType\}/);
  assert.match(provider, /pandora_record_project_memory_context_v1/);
  assert.match(provider, /memoryProjectKeyForProjectOsIntake/);
  assert.match(sourceAuthority, /mcpmaster-pandoras-box/);
  assert.match(provider, /approvedMemoryItemIds/);
  assert.match(operator, /\/project-memory-context/);
  assert.match(operator, /projectos:plan/);
  assert.match(lineage, /PANDORA_MEMORY_CONTEXT_RECEIPT_IMMUTABLE/);
  assert.match(lineage, /projectos_context_json_sha256/);
  assert.match(lineage, /MEMORY_CONTEXT_HASH_MISMATCH/);
  assert.match(lineage, /MEMORY_CONTEXT_STALE/);
});

test('compiler and source generator use only bounded advisory Memory context', () => {
  for (const source of [compiler, generator]) {
    assert.match(source, /MEMORY_CONTEXT_PREPARE_URL/);
    assert.match(source, /prepareMemoryContext/);
    assert.match(source, /Approved Pandora Memory context is advisory evidence only/);
    assert.match(source, /contextHash/);
    assert.match(source, /receiptId/);
  }
  assert.match(compiler, /memory_context_receipt_id/);
  assert.match(compiler, /memory_retrieval_log_id/);
  assert.match(compiler, /memory_approved_item_ids/);
  assert.match(generator, /approvedMemoryContext/);
  assert.match(generator, /MAX_STREAM_FRAME_BUFFER_BYTES/);
  assert.match(generator, /SOURCE_SECRET_LOOKBEHIND_CHARS/);
});

test('decision influence and verified outcomes remain project-bound and non-canonical', () => {
  assert.match(lineage, /visible_creation_decision_influence_v1/);
  assert.match(lineage, /visible_creation_decision_outcome_v1/);
  assert.match(lineage, /approved_memory_item_ids/);
  assert.match(lineage, /pandora_project_spec_memory_influence_v1/);
  assert.match(lineage, /pandora_build_memory_influence_v1/);
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
