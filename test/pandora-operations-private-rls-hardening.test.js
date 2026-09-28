'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync(
  'supabase/migrations/20260928072000_operations_private_rls_hardening_v1.sql',
  'utf8',
);

test('private Pandora server tables remain client-inaccessible and RLS hardened', () => {
  const tables = [
    'pandora_project_memory_context_receipts',
    'pandora_edge_function_retirement_receipts',
    'pandora_base44_identity_links',
    'pandora_google_workspace_oauth_states',
    'pandora_google_workspace_connections',
    'pandora_external_worker_dispatches',
    'pandora_coordinator_gate_decisions',
    'pandora_coordinator_gate_state',
    'pandora_coordinator_repository_fence',
    'pandora_coordinator_snapshot_promotions',
    'pandora_coordinator_snapshot_revocations',
    'pandora_ci_rescue_jobs',
    'phone_local_ai_acceptance_challenges',
    'phone_local_ai_acceptance_receipts',
    'plp_staff_task_action_receipts',
    'pandora_meta_oauth_states',
    'pandora_meta_connections',
    'pandora_meta_page_tokens',
  ];
  for (const table of tables) assert.match(migration,new RegExp("'"+table+"'"));
  assert.match(migration,/revoke all on schema private from public,anon,authenticated/);
  assert.match(migration,/to_regclass\('private\.'\|\|v_table\) is not null/);
  assert.match(migration,/execute format\('alter table private\.%I enable row level security',v_table\)/);
  assert.match(migration,/execute format\('revoke all on table private\.%I from public,anon,authenticated',v_table\)/);
});
