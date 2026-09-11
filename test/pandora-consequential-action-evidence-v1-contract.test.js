const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(join(root, 'supabase/migrations/20260912031000_pandora_consequential_action_evidence_v1.sql'), 'utf8');
const ownerApi = readFileSync(join(root, 'supabase/functions/pandora-owner-api/index.ts'), 'utf8');

test('terminal execution plans promote bounded truth into the existing evidence model', () => {
  assert.match(migration, /projectos_execution_outcome/);
  assert.match(migration, /private\.execution_plans/);
  assert.match(migration, /public\.projectos_evidence/);
  assert.match(migration, /resultSummarySha256/);
  assert.match(migration, /providerReadback/);
  assert.match(migration, /headSha/);
  assert.match(migration, /sourceVersion/);
  assert.doesNotMatch(migration, /'resultSummary',v_summary/);
});

test('evidence recording is idempotent and Activity receives a hash-chained summary event', () => {
  assert.match(migration, /on conflict \(organization_id,provider,evidence_type,external_id\) where external_id is not null do nothing/i);
  assert.match(migration, /private\.append_audit_event/);
  assert.match(migration, /projectos_execution_evidence_recorded/);
  assert.match(migration, /execution_plan_evidence_v1/);
  assert.match(ownerApi, /from\("audit_events"\)/);
});

test('owner action-evidence projection is authenticated-only and bounded', () => {
  assert.match(migration, /pandora_action_evidence_v1/);
  assert.match(migration, /least\(greatest\(coalesce\(p_limit,100\),1\),500\)/);
  assert.match(migration, /revoke all on function public\.pandora_action_evidence_v1\(uuid,integer\) from public,anon/);
  assert.match(migration, /grant execute on function public\.pandora_action_evidence_v1\(uuid,integer\) to authenticated/);
});

test('existing owner Evidence surface already consumes canonical projectos_evidence', () => {
  assert.match(ownerApi, /from\("projectos_evidence"\)/);
  assert.match(ownerApi, /payload_redacted/);
  assert.match(ownerApi, /observed_at/);
});
