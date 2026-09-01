-- Bind additive preview database execution to Pandora's governed Tool Gateway ledger.
-- This does not authorize production or destructive database work.

create or replace function private.pandora_authorize_database_change_execution_v1(
  p_plan_id uuid,
  p_preflight_verification_run_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','extensions','public'
as $$
declare
  v_plan public.pandora_database_change_plans%rowtype;
  v_runtime public.pandora_runtime_resources%rowtype;
  v_tool public.pandora_tool_calls%rowtype;
  v_args jsonb;
  v_args_sha text;
  v_target text;
  v_now timestamptz:=clock_timestamp();
begin
  if p_plan_id is null or p_preflight_verification_run_id is null
     or length(coalesce(p_idempotency_key,'')) not between 8 and 200 then
    raise exception 'invalid database execution authorization request' using errcode='22023';
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
     or v_plan.approval_required
     or v_plan.verification_run_id is distinct from p_preflight_verification_run_id
     or v_plan.action_hash is distinct from v_plan.migration_set_sha256 then
    raise exception 'database execution authorization blocked' using errcode='22023';
  end if;

  if not exists(
    select 1
    from public.pandora_verification_runs vr
    where vr.id=p_preflight_verification_run_id
      and vr.organization_id=v_plan.organization_id
      and vr.project_id=v_plan.project_id
      and vr.project_version_id=v_plan.project_version_id
      and vr.status='PASS'
      and vr.required_check_profile='database_change'
  ) then
    raise exception 'exact Worker E database preflight PASS required' using errcode='22023';
  end if;

  select * into v_runtime
  from public.pandora_runtime_resources
  where id=v_plan.target_runtime_resource_id;
  if not found
     or v_runtime.organization_id<>v_plan.organization_id
     or v_runtime.project_id<>v_plan.project_id
     or v_runtime.project_version_id is distinct from v_plan.project_version_id
     or v_runtime.environment<>'preview'
     or v_runtime.resource_type<>'database'
     or v_runtime.provider<>'supabase'
     or v_runtime.isolation_mode<>'shared_isolated'
     or v_runtime.status<>'ready' then
    raise exception 'exact isolated preview database required' using errcode='22023';
  end if;

  v_target:='database-plan:'||v_plan.id::text;
  v_args:=jsonb_build_object(
    'project_id',v_plan.project_id::text,
    'environment','preview',
    'migration_ref',v_target,
    'migration_kind','schema_change',
    'destructive',false,
    'request_id',p_idempotency_key,
    'idempotency_key',p_idempotency_key
  );
  v_args_sha:=encode(extensions.digest(convert_to(v_args::text,'utf8'),'sha256'),'hex');

  select * into v_tool
  from public.pandora_tool_calls
  where organization_id=v_plan.organization_id
    and action_hash=v_plan.action_hash
  for update;

  if found then
    if v_tool.project_id<>v_plan.project_id
       or v_tool.project_spec_id<>v_plan.project_spec_id
       or v_tool.project_version_id is distinct from v_plan.project_version_id
       or v_tool.tool_name<>'request_migration'
       or v_tool.tool_version<>'1'
       or v_tool.action_name<>'request_migration'
       or v_tool.environment<>'preview'
       or v_tool.target_resource_ref is distinct from v_target
       or v_tool.policy_version<>'pandora-tool-policy/1.1.0'
       or v_tool.arguments_sha256<>v_args_sha
       or v_tool.risk_level<>'MEDIUM'
       or v_tool.decision<>'ALLOW'
       or v_tool.side_effect<>'EXTERNAL_MUTATION'
       or v_tool.retry_mode<>'IDEMPOTENT_RETRY'
       or v_tool.idempotency_mode<>'REQUIRED'
       or v_tool.idempotency_key is distinct from p_idempotency_key
       or v_tool.approval_required
       or v_tool.status not in ('authorized','executing','succeeded') then
      raise exception 'database tool-call authorization collision' using errcode='23505';
    end if;
  else
    insert into public.pandora_tool_calls(
      organization_id,project_id,project_spec_id,project_version_id,
      tool_name,tool_version,action_name,environment,target_resource_ref,policy_version,
      action_hash,arguments_sha256,risk_level,decision,side_effect,retry_mode,
      idempotency_mode,idempotency_key,approval_required,status,requested_at
    ) values (
      v_plan.organization_id,v_plan.project_id,v_plan.project_spec_id,v_plan.project_version_id,
      'request_migration','1','request_migration','preview',v_target,'pandora-tool-policy/1.1.0',
      v_plan.action_hash,v_args_sha,'MEDIUM','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY',
      'REQUIRED',p_idempotency_key,false,'authorized',v_now
    )
    returning * into v_tool;
  end if;

  if v_plan.execution_tool_call_id is not null and v_plan.execution_tool_call_id<>v_tool.id then
    raise exception 'database plan already bound to another tool call' using errcode='23505';
  end if;

  update public.pandora_database_change_plans
  set execution_tool_call_id=v_tool.id,
      updated_at=v_now
  where id=v_plan.id
    and status='approved'
    and (execution_tool_call_id is null or execution_tool_call_id=v_tool.id);
  if not found then
    raise exception 'database plan authorization claim conflict' using errcode='40001';
  end if;

  return jsonb_build_object(
    'planId',v_plan.id,
    'toolCallId',v_tool.id,
    'status',v_tool.status,
    'decision',v_tool.decision,
    'risk',v_tool.risk_level,
    'environment',v_tool.environm,
    'preflightVerificationRunId',p_preflight_verification_run_id,
    'replayed',v_tool.requested_at<v_now
  );
end;
$$;

revoke all on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role;

create or replace function public.pandora_authorize_database_change_execution_v1(
  p_plan_id uuid,
  p_preflight_verification_run_id uuid,
  p_idempotency_key text
)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select private.pandora_authorize_database_change_execution_v1($1,$2,$3);
$$;
revoke all on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role;

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
  v_expected:=encode(extensions.digest(convert_to('create_table:'||v_schema||'.'||p_table_name||':id_uuid,value_text,created_at_timestamptz','utf8'),'sha256'),'hex');
  if v_expected<>v_plan.migration_set_sha256
     or exists(select 1 from information_schema.tables where table_schema=v_schema and table_name=p_table_name) then
    raise exception 'database migration identity conflict' using errcode='23505';
  end if;

  update public.pandora_tool_calls
  set status='executing',started_at=v_now
  where id=v_tool.id and status='authorized';
  if not found then raise exception 'migration tool-call claim conflict' using errcode='40001'; end if;

  update public.pandora_database_change_plans
  set status='executing',started_at=v_now,updated_at=v_now
  where id=v_plan.id and status='approved' and execution_tool_call_id=v_tool.id;
  if not found then raise exception 'database plan execution claim conflict' using errcode='40001'; end if;

  execute format('create table %I.%I(id uuid primary key default gen_random_uuid(), value text not null, created_at timestamptz not null default now())',v_schema,p_table_name);
  execute format('grant select,insert,update,delete on %I.%I to %I',v_schema,p_table_name,v_res.configuration_redacted->>'databaseRole');

  select encode(extensions.digest(convert_to(coalesce(string_agg(table_name||':'||column_name||':'||data_type||':'||is_nullable,E'\n' order by table_name,ordinal_position),''),'utf8'),'sha256'),'hex')
  into v_after
  from information_schema.columns
  where table_schema=v_schema;

  update public.pandora_database_change_plans
  set status='applied',schema_after_sha256=v_after,
      schema_diff_sha256=encode(extensions.digest(convert_to(schema_before_sha256||':'||v_after,'utf8'),'sha256'),'hex'),
      applied_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_plan.id and status='executing' and execution_tool_call_id=v_tool.id;
  if not found then raise exception 'database apply state write failed' using errcode='55000'; end if;

  update public.pandora_tool_calls
  set status='succeeded',completed_at=clock_timestamp()
  where id=v_tool.id and status='executing';
  if not found then raise exception 'migration tool-call completion write failed' using errcode='55000'; end if;

  return jsonb_build_object(
    'planId',v_plan.id,
    'toolCallId',v_tool.id,
    'status','applied',
    'schema',v_schema,
    'table',p_table_name,
    'schemaAfterSha256',v_after,
    'authorizationRef',p_authorization_ref
  );
end;
$$;

revoke all on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;
revoke all on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;
