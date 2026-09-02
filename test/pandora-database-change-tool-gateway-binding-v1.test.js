'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const base = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20260902023000_pandora_database_change_tool_gateway_binding_v1.sql'),
  'utf8',
);
const fix = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20260902043800_pandora_database_change_apply_identity_fix_v1.sql'),
  'utf8',
);

function hasBase(value) { assert.ok(base.includes(value), `missing base: ${value}`); }
function hasFix(value) { assert.ok(fix.includes(value), `missing fix: ${value}`); }

test('authorization is service-only and restricted to additive isolated preview changes', () => {
  hasBase('pandora_authorize_database_change_execution_v1');
  hasBase("v_plan.environment<>'preview'");
  hasBase('v_plan.destructive_change');
  hasBase('not v_plan.backward_compatible');
  hasBase("v_plan.lock_risk not in ('low','none')");
  hasBase('v_plan.approval_required');
  hasBase("v_runtime.isolation_mode<>'shared_isolated'");
  hasBase("v_runtime.provider<>'supabase'");
  hasBase('revoke all on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated');
  hasBase('grant execute on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role');
});

test('authorization requires exact independent Worker E preflight lineage', () => {
  hasBase("vr.status='PASS'");
  hasBase("vr.required_check_profile='database_change'");
  hasBase('vr.project_version_id=v_plan.project_version_id');
  hasBase('v_plan.verification_run_id is distinct from p_preflight_verification_run_id');
});

test('tool call mirrors request_migration registry and policy contract', () => {
  for (const value of [
    "'request_migration','1','request_migration','preview'",
    "'pandora-tool-policy/1.1.0'",
    "'MEDIUM','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY'",
    "'REQUIRED',p_idempotency_key,false,'authorized'",
  ]) hasBase(value);
  hasBase("v_target:='database-plan:'||v_plan.id::text");
  hasBase('set execution_tool_call_id=v_tool.id');
  hasBase('database tool-call authorization collision');
  hasBase('database plan already bound to another tool call');
});

test('effective apply path preserves immutable plan identity and validates actual hashes', () => {
  hasFix("v_tool.status<>'authorized'");
  hasFix("p_authorization_ref is distinct from 'worker-c:tool-call:'||v_tool.id::text");
  hasFix("set status='executing',started_at=v_now");
  hasFix('v_after is distinct from v_plan.schema_after_sha256');
  hasFix('v_diff is distinct from v_plan.schema_diff_sha256');
  hasFix("raise exception 'database apply schema identity mismatch'");
  hasFix("set status='applied',applied_at=clock_timestamp(),updated_at=clock_timestamp()");
  hasFix("set status='succeeded',completed_at=clock_timestamp()");
  hasFix('migration tool-call claim conflict');
  hasFix('database plan execution claim conflict');
  hasFix('migration tool-call completion write failed');
  assert.ok(!fix.includes('schema_after_sha256=v_after'));
  assert.ok(!fix.includes('schema_diff_sha256='));
});

test('corrective migration preserves service-only execution boundary', () => {
  hasFix('revoke all on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated');
  hasFix('grant execute on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role');
  hasFix('revoke all on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated');
  hasFix('grant execute on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role');
});

test('production and destructive execution are not silently authorized by this bridge', () => {
  assert.equal((base.match(/environment<>'preview'/g) || []).length >= 2, true);
  assert.equal((base.match(/destructive_change/g) || []).length >= 2, true);
  assert.ok(!base.includes("environment='production' and decision='ALLOW'"));
});
