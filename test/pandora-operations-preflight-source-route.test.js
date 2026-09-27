'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260927090000_operations_preflight_source_route_v1.sql','utf8');
const worker = fs.readFileSync('api/operations-native-worker.ts','utf8');
const control = fs.readFileSync('supabase/functions/mcpmaster-supabase-control/index.ts','utf8');

test('arbitrary Operations preflight is source-tracked and service-role only', () => {
  assert.match(migration,/pandora_ops_preflight_next_v1/);
  assert.match(migration,/for update skip locked/i);
  assert.match(migration,/task_preflight_completed/);
  assert.match(migration,/do_not_infer_or_satisfy_human_authority/);
  assert.match(migration,/grant execute on function public\.pandora_ops_preflight_next_v1[\s\S]*service_role/);
  assert.doesNotMatch(migration,/task_key like 'FB-%'/);
  assert.match(migration,/reasoning_rdp_ready/);
  assert.match(migration,/task_key !~ '\^OPS-\(RDP-\(AUTO\|DIRECT\)\|CHATGPT-DIRECT\)-'/);
});
test('native source selector excludes external-worker routed tasks', () => {
  assert.match(migration,/verification->>'executionRoute'[\s\S]*external_worker_required/);
});
test('native worker preflights queued tracker work before idling', () => {
  const candidateAt=worker.indexOf('action: "operations_generic_source_candidate"');
  const preflightAt=worker.indexOf('action: "operations_preflight_next"');
  assert.ok(candidateAt >= 0 && preflightAt > candidateAt);
  assert.match(worker,/state:\s*"preflighted"/);
});
test('OIDC control exposes fixed preflight RPC', () => {
  assert.match(control,/pandora_ops_preflight_next_v1/);
  assert.match(control,/operations_preflight_next/);
  assert.match(control,/p_worker_key:\s*worker\.workerKey/);
  assert.match(control,/p_principal_key:\s*worker\.principalKey/);
});
