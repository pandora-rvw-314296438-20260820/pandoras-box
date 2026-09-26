'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260926142630_operations_generic_source_worker_v1.sql','utf8');
const worker = fs.readFileSync('api/operations-native-worker.ts','utf8');
const control = fs.readFileSync('supabase/functions/mcpmaster-supabase-control/index.ts','utf8');

test('generic source worker remains lease, human-gate, ancestry and Vault fenced', () => {
  assert.match(migration,/pandora_ops_generic_source_candidate_v1/);
  assert.match(migration,/pandora_ops_generic_source_execute_v1/);
  assert.match(migration,/pandora_ops_generic_source_release_step_v1/);
  assert.match(migration,/pandora_ops_human_gates/);
  assert.match(migration,/FB-003[\s\S]*owner_decision[\s\S]*blocked/);
  assert.match(migration,/FB-007[\s\S]*privacy_approval[\s\S]*blocked/);
  assert.match(migration,/FB-011[\s\S]*interactive_oauth[\s\S]*blocked/);
  assert.match(migration,/pandora_ops_leases[\s\S]*state='running'/);
  assert.match(migration,/compare\/[\s\S]*v_requested_base[\s\S]*v_main/);
  assert.match(migration,/pandora_direct_box_code_edit_v1/);
  assert.match(migration,/pandora_coordinator_gate_invoke_v1/);
  assert.match(migration,/pandora_coordinator_vault_merge_v1/);
  assert.match(migration,/pandora_ops_record_verification_v1/);
  assert.match(migration,/pandora_ops_verify_v1/);
  assert.doesNotMatch(migration,/github_pat_|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,}/);
});

test('native Vercel worker claims generic source tasks rather than one hard-coded canary', () => {
  assert.match(worker,/maxDuration:\s*300/);
  assert.match(worker,/operations_generic_source_release_step/);
  assert.match(worker,/operations_generic_source_candidate/);
  assert.match(worker,/operations_generic_source_execute/);
  assert.match(worker,/GENERIC_SOURCE_EXECUTION_UNCONFIRMED/);
  assert.doesNotMatch(worker,/entry\?\.status === "queued" && entry\?\.spec\?\.id === CANARY_TASK/);
});

test('OIDC control exposes fixed source RPCs and broadens builder lanes', () => {
  assert.match(control,/pandora_ops_generic_source_candidate_v1/);
  assert.match(control,/pandora_ops_generic_source_execute_v1/);
  assert.match(control,/pandora_ops_generic_source_release_step_v1/);
  assert.match(control,/lanes:\s*\["backend", "reliability", "web", "growth"\]/);
  assert.match(control,/verifyVercelToken/);
});
