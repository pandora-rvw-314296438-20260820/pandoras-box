'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const migration = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    'supabase',
    'migrations',
    '20260902045500_pandora_database_change_action_binding_v2.sql',
  ),
  'utf8',
);
const gateway = fs.readFileSync(
  path.join(__dirname, '..', 'packages', 'pandora-tools', 'src', 'gateway.js'),
  'utf8',
);
const contracts = fs.readFileSync(
  path.join(__dirname, '..', 'packages', 'pandora-tools', 'src', 'contracts.js'),
  'utf8',
);
const durable = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    'supabase',
    'migrations',
    '20260828170000_pandora_durable_execution_lineage_v1.sql',
  ),
  'utf8',
);

function has(value) {
  assert.ok(migration.includes(value), `missing action-binding repair: ${value}`);
}

test('database migration action binding follows the canonical Tool Gateway envelope', () => {
  assert.ok(gateway.includes('const actionHash = computeActionHash({'));
  assert.ok(
    contracts.includes(
      'function computeActionHash({ tool, version, arguments: args, organization_id, project_id, environment, target_resource = null, project_version = null, policy_version })',
    ),
  );
  for (const value of [
    "'tool','request_migration'",
    "'version',1",
    "'arguments',v_args",
    "'organization_id',p_organization_id::text",
    "'project_id',p_project_id::text",
    "'environment',p_environment",
    "'target_resource',v_target",
    "'project_version',p_project_version_id::text",
    "'policy_version','pandora-tool-policy/1.1.0'",
    'private.projectos_canonical_context_json(v_envelope)',
  ]) has(value);
});

test('migration digest and plan-bound action hash are distinct identities', () => {
  has("v_migration_sha:=encode(extensions.digest(convert_to(v_migration,'utf8'),'sha256'),'hex')");
  has("v_action:=v_binding->>'actionHash'");
  has("v_res.environment,'reviewed',v_migration_sha,v_before,v_after,v_diff,v_action");
  has('v_existing.migration_set_sha256<>v_migration_sha');
  has('v_existing.action_hash<>v_action');
  assert.ok(!migration.includes('v_plan.action_hash is distinct from v_plan.migration_set_sha256'));
  assert.ok(!migration.includes('action_hash=v_migration_sha'));
});

test('successor authorization is exact-plan bound without weakening action uniqueness', () => {
  assert.ok(
    durable.includes(
      'create unique index if not exists pandora_tool_calls_action_uidx on public.pandora_tool_calls(organization_id,action_hash);',
    ),
  );
  has("v_target:='database-plan:'||p_plan_id::text");
  has('v_plan.idempotency_key is distinct from p_idempotency_key');
  has('v_plan.action_hash is distinct from v_action');
  has('where organization_id=v_plan.organization_id');
  has('and action_hash=v_action');
  has('v_tool.target_resource_ref is distinct from v_target');
  has('v_tool.arguments_sha256<>v_args_sha');
  has("v_tool.status not in ('authorized','executing','succeeded')");
});

test('canonical argument digest is bound to the exact request_migration arguments', () => {
  for (const value of [
    "'project_id',p_project_id::text",
    "'environment',p_environment",
    "'migration_ref',v_target",
    "'migration_kind','schema_change'",
    "'destructive',false",
    "'request_id',p_idempotency_key",
    "'idempotency_key',p_idempotency_key",
    'private.projectos_canonical_context_json(v_args)',
    "'argumentsSha256',v_args_sha",
  ]) has(value);
});

test('action-binding repair remains service-role only', () => {
  for (const value of [
    'revoke all on function private.pandora_database_change_request_migration_binding_v1(uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated',
    'grant execute on function private.pandora_database_change_request_migration_binding_v1(uuid,uuid,uuid,uuid,text,text) to service_role',
    'revoke all on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated',
    'grant execute on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) to service_role',
    'revoke all on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated',
    'grant execute on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role',
  ]) has(value);
});
