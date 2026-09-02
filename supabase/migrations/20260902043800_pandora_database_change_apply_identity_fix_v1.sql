-- Task 146 repair: keep DatabaseChangePlan identity immutable during governed preview apply.
-- The original apply RPC attempted to rewrite schema_after_sha256/schema_diff_sha256 even
-- though the plan guard correctly treats those fields as immutable. This forward-only
-- replacement verifies the actual post-DDL hashes against the precomputed plan identity.

create or replace function private.pandora_worker_f_apply_isolated_create_table_20260829(
  p_plan_id uuid,
  p_table_name text,
  p_authorization_ref text,
  p_preflight_verification_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
  v_plan public.pandora_database_change_plans%rowtype;
  v_res public.pandora_runtime_resources%rowtype;
  v_tool public.pandora_tool_calls%rowtype;
  v_schema text;
  v_expected text;
  v_after text;
  v_diff text;
  v_now timestamptz:=clock_timestamp();
begin
  if p_table_name !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'invalid authorized database execution' using errcode='22023';
  end if;

  select * into v_plan
  from public.pandora_database_change_plans
  where id=p_plan_id
  for update;
  if not found
     or v_plan.status<>'approved'
     or v_plan.environment<>'preview'
     or v_plan.destructive_change
     or not v_plan.backward_compatible
     or v_plan.lock_risk not in ('low','none')
     or v_plan.verification_run_id is distinct from p_preflight_verification_run_id
     or v_plan.execution_tool_call_id is null then
    raise exception 'approved tool-bound preview preflight required' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.pandora_verification_runs
    where id=p_preflight_verification_run_id
      and organization_id=v_plan.organization_id
      and project_id=v_plan.project_id
      and project_version_id=v_plan.project_version_id
      and status='PASS'
      and required_check_profile='database_change'
  ) then
    raise exception 'Worker E preflight PASS required' using errcode='22023';
  end if;

  select * into v_tool
  from public.pandora_tool_calls
  where id=v_plan.execution_tool_call_id
  for update;
  if not found
     or v_tool.organization_id<>v_plan.organization_id
     or v_tool.project_id<>v_plan.project_id
     or v_tool.project_spec_id<>v_plan.project_spec_id
     or v_tool.project_version_id is distinct from v_plan.project_version_id
     or v_tool.tool_name<>'request_migration'
     or v_tool.tool_version<>'1'
     or v_tool.action_name<>'request_migration'
     or v_tool.environment<>'preview'
     or v_tool.target_resource_ref is distinct from 'database-plan:'||v_plan.id::text
     or v_tool.policy_version<>'pandora-tool-policy/1.1.0'
     or v_tool.action_hash<>v_plan.action_hash
     or v_tool.risk_level<>'MEDIUM'
     or v_tool.decision<>'ALLOW'
     or v_tool.side_effect<>'EXTERNAL_MUTATION'
     or v_tool.retry_mode<>'IDEMPOTENT_RETRY'
     or v_tool.idempotency_mode<>'REQUIRED'
     or v_tool.approval_required
     or v_tool.status<>'authorized'
     or p_authorization_ref is distinct from 'worker-c:tool-call:'||v_tool.id::text then
    raise exception 'exact authorized migration tool call required' using errcode='22023';
  end if;

  select * into v_res
  from public.pandora_runtime_resources
  where id=v_plan.target_runtime_resource_id and status='ready';
  if not found
     or v_res.environment<>'preview'
     or v_res.resource_type<>'database'
     or v_res.provider<>'supabase'
     or v_res.isolation_mode<>'shared_isolated' then
    raise exception 'isolated preview database unavailable' using errcode='22023';
  end if;

  v_schema:=v_res.configuration_redacted->>'schema';
  v_expected:=encode(
    extensions.digest(
      convert_to(
        'create_table:'||v_schema||'.'||p_table_name||':id_uuid,value_text,created_at_timestamptz',
        'utf8'
      ),
      'sha256'
    ),
    'hex'
  );
  if v_expected<>v_plan.migration_set_sha256
     or exists(
       select 1
       from information_schema.tables
       where table_schema=v_schema and table_name=p_table_name
     ) then
    raise exception 'database migration identity conflict' using errcode='23505';
  end if;

  update public.pandora_tool_calls
  set status='executing',started_at=v_now
  where id=v_tool.id and status='authorized';
  if not found then
    raise exception 'migration tool-call claim conflict' using errcode='40001';
  end if;

  update public.pandora_database_change_plans
  set status='executing',started_at=v_now,updated_at=v_now
  where id=v_plan.id and status='approved' and execution_tool_call_id=v_tool.id;
  if not found then
    raise exception 'database plan execution claim conflict' using errcode='40001';
  end if;

  execute format(
    'create table %I.%I(id uuid primary key default gen_random_uuid(), value text not null, created_at timestamptz not null default now())',
    v_schema,
    p_table_name
  );
  execute format(
    'grant select,insert,update,delete on %I.%I to %I',
    v_schema,
    p_table_name,
    v_res.configuration_redacted->>'databaseRole'
  );

  select encode(
    extensions.digest(
      convert_to(
        coalesce(
          string_agg(
            table_name||':'||column_name||':'||data_type||':'||is_nullable,
            E'\n'
            order by table_name,ordinal_position
          ),
          ''
        ),
        'utf8'
      ),
      'sha256'
    ),
    'hex'
  )
  into v_after
  from information_schema.columns
  where table_schema=v_schema;

  v_diff:=encode(
    extensions.digest(
      convert_to(v_plan.schema_before_sha256||':'||v_after,'utf8'),
      'sha256'
    ),
    'hex'
  );

  if v_after is distinct from v_plan.schema_after_sha256
     or v_diff is distinct from v_plan.schema_diff_sha256 then
    raise exception 'database apply schema identity mismatch' using errcode='55000';
  end if;

  update public.pandora_database_change_plans
  set status='applied',applied_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_plan.id and status='executing' and execution_tool_call_id=v_tool.id;
  if not found then
    raise exception 'database apply state write failed' using errcode='55000';
  end if;

  update public.pandora_tool_calls
  set status='succeeded',completed_at=clock_timestamp()
  where id=v_tool.id and status='executing';
  if not found then
    raise exception 'migration tool-call completion write failed' using errcode='55000';
  end if;

  return jsonb_build_object(
    'planId',v_plan.id,
    'toolCallId',v_tool.id,
    'status','applied',
    'schema',v_schema,
    'table',p_table_name,
    'schemaAfterSha256',v_after,
    'schemaDiffSha256',v_diff,
    'authorizationRef',p_authorization_ref
  );
end;
$$;

revoke all on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;
revoke all on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;
