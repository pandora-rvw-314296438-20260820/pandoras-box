
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migration = readFileSync(
  join(process.cwd(),'supabase','migrations','20260828193000_pandora_realtime_audit_security_v1.sql'),
  'utf8',
);

test('Worker A publishes only a safe Build Theatre projection', () => {
  const start = migration.indexOf('create table if not exists public.pandora_build_theatre_projection');
  const end = migration.indexOf('create or replace function private.pandora_build_theatre_owner_stage');
  assert.ok(start >= 0 && end > start);
  const projection = migration.slice(start,end);
  for (const forbidden of [
    'lease_owner','lease_token_sha256','worker_identity','error_code',
    'model_run_id','tool_call_id','arguments','prompt','secret_value','credential',
  ]) assert.doesNotMatch(projection,new RegExp(forbidden,'i'),forbidden);
  for (const required of [
    'owner_state','owner_stage','progress_percent','public_message',
    'preview_url','live_url','needs_you','retry_available',
  ]) assert.match(projection,new RegExp(required));
  const publicationAdds = [...migration.matchAll(/alter publication supabase_realtime add table ([a-z0-9_.]+)/gi)]
    .map((match) => match[1]);
  assert.deepEqual(publicationAdds,['public.pandora_build_theatre_projection']);
  assert.match(migration,/pandora_build_theatre_projection_member_read/);
  assert.match(migration,/grant select on table public\.pandora_build_theatre_projection to authenticated/);
  assert.doesNotMatch(migration,/grant (?:insert|update|delete|all).*pandora_build_theatre_projection to authenticated/i);
});

test('Worker A extends the existing immutable audit chain with project addressing', () => {
  for (const required of [
    'alter table public.audit_events','project_id uuid null','request_id text null',
    'idempotency_key text null','resource_type text null','resource_id uuid null',
    'action_hash text null','provenance_redacted jsonb','append_project_audit_event',
    'previous_hash','event_hash','pg_advisory_xact_lock','pandora_control_plane_audit_trigger',
  ]) assert.ok(migration.includes(required),required);
  for (const table of [
    'pandora_project_intents','pandora_project_specs','pandora_build_jobs',
    'pandora_verification_runs','pandora_policy_actions','approvals',
    'pandora_project_versions','pandora_project_deployments','pandora_project_domains',
    'pandora_budget_limits','pandora_runtime_resources','pandora_secret_references',
    'pandora_database_change_plans',
  ]) assert.ok(migration.includes(`'${table}'`),`audit trigger missing ${table}`);
  assert.match(migration,/Never copies full control-plane rows/);
  assert.match(migration,/revoke insert,update,delete on table public\.audit_events from public,anon,authenticated,service_role/);
});

test('Worker A removes direct customer mutation of release and provider truth', () => {
  for (const table of ['pandora_project_versions','pandora_project_deployments','pandora_project_domains']) {
    assert.match(migration,new RegExp(`revoke insert,update,delete on table public\\.${table} from authenticated`));
    assert.match(migration,new RegExp(`grant select on table public\\.${table} to authenticated`));
  }
  for (const policy of [
    'pandora_project_versions_operator_write',
    'pandora_project_deployments_operator_write',
    'pandora_project_domains_operator_write',
  ]) assert.ok(migration.includes(`drop policy if exists ${policy}`),policy);
  for (const triggerFunction of [
    'pandora_record_build_job_state_event','pandora_validate_artifact_version_lineage',
    'pandora_validate_build_job_child','pandora_validate_build_job_lineage',
    'pandora_validate_control_plane_scope','pandora_validate_policy_action',
    'pandora_validate_project_version_control_plane','pandora_validate_verification_identity',
    'pandora_validate_budget_limit_scope','pandora_validate_cost_entry_scope',
    'pandora_validate_project_node_scope','pandora_validate_project_relationship_scope',
    'pandora_validate_runtime_resource_scope','pandora_validate_secret_reference_scope',
    'pandora_validate_database_change_plan','pandora_validate_database_change_item_scope',
  ]) assert.ok(migration.includes(`private.${triggerFunction}`),triggerFunction);
});

test('Worker A final indexes match active control-plane access paths', () => {
  for (const index of [
    'pandora_build_theatre_projection_org_state_idx','audit_events_project_id_desc_idx',
    'audit_events_resource_desc_idx','audit_events_org_idempotency_idx',
    'pandora_build_jobs_project_active_stage_idx','pandora_project_versions_live_idx',
    'pandora_project_versions_verification_idx','pandora_verification_runs_project_status_idx',
    'pandora_policy_actions_project_pending_idx',
  ]) assert.ok(migration.includes(index),index);
});

test('Worker A Realtime and audit helpers remain private service boundaries', () => {
  for (const fn of [
    'pandora_sync_build_theatre_from_job()','pandora_sync_build_theatre_from_deployment()',
    'pandora_sync_build_theatre_from_version()','pandora_sync_build_theatre_from_domain()',
    'pandora_control_plane_audit_trigger()',
  ]) {
    assert.ok(
      migration.includes(`revoke all on function private.${fn} from public,anon,authenticated`) ||
      migration.includes(`revoke execute on function private.${fn} from public,anon,authenticated`),
      fn,
    );
  }
});

const controlPlaneDoc = readFileSync(
  join(process.cwd(),'docs','architecture','PANDORA_CONTROL_PLANE_V1.md'),
  'utf8',
);

test('Control Plane V1 documentation is bound to implemented source contracts', () => {
  for (const migrationName of [
    '20260828153500_pandora_project_spec_control_plane_v1.sql',
    '20260828170000_pandora_durable_execution_lineage_v1.sql',
    '20260828181500_pandora_economics_runtime_safety_v1.sql',
    '20260828193000_pandora_realtime_audit_security_v1.sql',
  ]) assert.ok(controlPlaneDoc.includes(migrationName),migrationName);
  for (const contract of [
    'pandora_project_specs','pandora_build_jobs','pandora_model_runs','pandora_tool_calls',
    'pandora_artifacts','pandora_verification_runs','pandora_policy_actions',
    'pandora_budget_limits','pandora_cost_entries','pandora_project_nodes',
    'pandora_runtime_resources','pandora_secret_references','pandora_database_change_plans',
    'pandora_build_theatre_projection','audit_events',
  ]) assert.ok(controlPlaneDoc.includes(contract),contract);
  assert.match(controlPlaneDoc,/Worker F: preview\/production\/runtime provider execution/);
  assert.match(controlPlaneDoc,/It never stores the credential value/);
  assert.match(controlPlaneDoc,/only Worker A table intentionally added to `supabase_realtime`/);
});
