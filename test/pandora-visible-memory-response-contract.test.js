const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260903013000_pandora_visible_memory_response_contract_v2.sql'),
  'utf8',
);

test('visible Memory delivery requires explicit review-gated non-canonical response', () => {
  assert.match(migration, /learning_kind',''\) <> 'visible_creation_evidence_v1'/);
  assert.match(migration, /review_required',''\)='true'/);
  assert.match(migration, /canonical_memory_written',''\)='false'/);
  assert.match(migration, /source_event_id/);
  assert.match(migration, /visible_project_id/);
  assert.match(migration, /candidate_id/);
  assert.match(migration, /review_item_id/);
});

test('legacy learning keeps clean-HTTP behavior while visible invalid 200 retries', () => {
  assert.match(migration, /if coalesce\(p_payload->>'learning_kind',''\) <> 'visible_creation_evidence_v1' then\s+return true;/);
  assert.match(migration, /invalid learning response contract/);
  assert.match(migration, /when latest\.response_valid then 'delivered'/);
  assert.match(migration, /else 'pending'/);
});

test('response validator is private and fail closed on non-JSON visible body', () => {
  assert.match(migration, /v_body := p_content::jsonb;\s+exception when others then\s+return false;/);
  assert.match(migration, /revoke all on function private\.execution_learning_response_is_valid/);
  assert.match(migration, /revoke all on function private\.reconcile_execution_learning_responses/);
});
