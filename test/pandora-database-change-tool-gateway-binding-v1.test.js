'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260902023000_pandora_database_change_tool_gateway_binding_v1.sql'), 'utf8');

function has(value) { assert.ok(migration.includes(value), `missing: ${value}`); }

test('authorization is service-only and restricted to additive isolated preview changes', () => {
  has('pandora_authorize_database_change_execution_v1');
  has("v_plan.environment<>'preview'");
  has('v_plan.destructive_change');
  has('not v_plan.backward_compatible');
  has("v_plan.lock_risk not in ('low','none')");
  has('v_plan.approval_required');
  has("v_runtime.isolation_mode<>'shared_isolated'");
  has("v_runtime.provider<>'supabase'");
  has('revoke all on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated');
  has('grant execute on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role');
});

test('authorization requires exact independent Worker E preflight lineage', () => {
  has("vr.status='PASS'");
  has("vr.required_check_profile='database_change'");
  has('vr.project_version_id=v_plan.project_version_id');
  has('v_plan.verification_run_id is distinct from p_preflight_verification_run_id');
});

test('tool call mirrors request_migration registry and policy contract', () => {
  for (const value of [
    "'request_migration','1','request_migration','preview'",
    "'pandora-tool-policy/1.1.0'",
    "'MEDIUM','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY'",
    "'REQUIRED',p_idempotency_key,false,'authorized'",
  ]) has(value);
  has("v_target:='database-plan:'||v_plan.id::text");
  has('set execution_tool_call_id=v_tool.id');
  has('database tool-call authorization collision');
  has('database plan already bound to another tool call');
});

test('apply requires the exact bound tool call and advances both ledgers atomically', () => {
  has("v_tool.status<>'authorized'");
  has("p_authorization_ref is distinct from 'worker-c:tool-call:'||v_tool.id::text");
  has("set status='executing',started_at=v_now");
  has("set status='applied',schema_after_sha256=v_after");
  has("set status='succeeded',completed_at=clock_timestamp()");
  has('migration tool-call claim conflict');
  has('database plan execution claim conflict');
  has('migration tool-call completion write failed');
});

test('production and destructive execution are not silently authorized by this bridge', () => {
  assert.equal((migration.match(/environment<>'preview'/g) || []).length >= 2, true);
  assert.equal((migration.match(/destructive_change/g) || []).length >= 2, true);
  assert.ok(!migration.includes("environment='production' and decision='ALLOW'"));
});
