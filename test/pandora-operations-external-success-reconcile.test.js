'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260928072000_operations_external_success_reconcile_and_private_rls_v1.sql',
  'utf8',
);

test('external success reconciliation is exact-task, lease, authority and provider-readback fenced', () => {
  assert.match(migration,/pandora_ops_reconcile_external_success_v1/);
  assert.match(migration,/l\.state<>'reconcile'/);
  assert.match(migration,/t\.status<>'blocked'/);
  assert.match(migration,/OPS_EXTERNAL_RECONCILE_DISPATCH_EXISTS/);
  assert.match(migration,/providerOutcomeKnown/);
  assert.match(migration,/externalActorFenced/);
  assert.match(migration,/release\/pr\//);
  assert.match(migration,/git\/branch\//);
  assert.match(migration,/pandora_integration_github_api_20260825/);
  assert.match(migration,/compare\//);
  assert.match(migration,/OPS_EXTERNAL_RECONCILE_ANCESTRY_MISMATCH/);
  assert.match(migration,/pandora_ops_settle_v1/);
  assert.match(migration,/status='queued'/);
  assert.match(migration,/external_provider_success_reconciled/);
  assert.doesNotMatch(migration,/set status='complete'/);
  assert.doesNotMatch(migration,/github_pat_|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,}/);
});

test('private server tables are RLS hardened without client grants', () => {
  const tables = [
    'pandora_project_memory_context_receipts','pandora_edge_function_retirement_receipts',
    'pandora_base44_identity_links','pandora_google_workspace_oauth_states',
    'pandora_google_workspace_connections','pandora_external_worker_dispatches',
    'pandora_coordinator_gate_decisions','pandora_coordinator_gate_state',
    'pandora_coordinator_repository_fence','pandora_coordinator_snapshot_promotions',
    'pandora_coordinator_snapshot_revocations','pandora_ci_rescue_jobs',
    'phone_local_ai_acceptance_challenges','phone_local_ai_acceptance_receipts',
    'plp_staff_task_action_receipts','pandora_meta_oauth_states',
    'pandora_meta_connections','pandora_meta_page_tokens',
  ];
  for (const table of tables) {
    assert.match(migration,new RegExp('alter table if exists private\\.'+table+' enable row level security'));
  }
  assert.match(migration,/revoke all on schema private from public,anon,authenticated/);
  assert.match(migration,/from public,anon,authenticated/);
  assert.match(migration,/grant execute on function public\.pandora_ops_reconcile_external_success_v1[\s\S]*to service_role/);
});
