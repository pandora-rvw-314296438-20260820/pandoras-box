-- Task 146 follow-up: bind DatabaseChangePlan actions to the canonical Tool Gateway envelope.
--
-- migration_set_sha256 remains the digest of the migration intent. action_hash instead binds the
-- exact request_migration tool action (arguments, scope, target plan, project version, policy).
-- This preserves the global (organization_id, action_hash) uniqueness invariant while allowing a
-- corrected successor plan to coexist with a cancelled historical plan for the same migration intent.

create or replace function private.pandora_database_change_request_migration_binding_v1(
  p_plan_id uuid,
  p_organization_id uuid,
  p_project_id uuid,
  p_project_version_id uuid,
  p_environment text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path='pg_catalog','private','extensions'
as $$
declare
  v_target text;
  v_args jsonb;
  v_envelope jsonb;
  v_args_sha text;
  v_action_hash text;
begin
  if p_plan_id is null
     or p_organization_id is null
     or p_project_id is null
     or p_environment not in ('development','preview','production')
     or length(coalesce(p_idempotency_key,'')) not between 8 and 200 then
    raise exception 'invalid database migration action binding' using errcode='22023';
  end if;

  v_target:='database-plan:'||p_plan_id::text;
  v_args:=jsonb_build_object(
    'project_id',p_project_id::text,
    'environment',p_environment,
    'migration_ref',v_target,
    'migration_kind','schema_change',
    'destructive',false,
    'request_id',p_idempotency_key,
    'idempotency_key',p_idempotency_key
  );

  v_envelope:=jsonb_build_object(
    'tool','request_migration',
    'version',1,
    'arguments',v_args,
    'organization_id',p_organization_id::text,
    'project_id',p_project_id::text,
    'environment',p_environment,
    'target_resource',v_target,
    'project_version',p_project_version_id::text,
    'policy_version','pandora-tool-policy/1.1.0'
  );

  v_args_sha:=encode(
    extensions.digest(
      convert_to(private.projectos_canonical_context_json(v_args),'utf8'),
      'sha256'
    ),
    'hex'
  );
  v_action_hash:=encode(
    extensions.digest(
      convert_to(private.projectos_canonical_context_json(v_envelope),'utf8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'targetResource',v_target,
    'arguments',v_args,
    'argumentsSha256',v_args_sha,
    'actionHash',v_action_hash
  );
end;
$$;

revoke all on function private.pandora_database_change_request_migration_binding_v1(uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.pandora_database_change_request_migration_binding_v1(uuid,uuid,uuid,uuid,text,text) to service_role;

create or replace function private.pandora_worker_f_plan_isolated_create_table_20260829(
  p_runtime_resource_id uuid,
  p_project_spec_id uuid,
  p_project_version_id uuid,
  p_table_name text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $$
declare
  v_res public.pandora_runtime_resources%rowtype;
  v_existing public.pandora_database_change_plans%rowtype;
  v_schema text;
  v_before text;
  v_after text;
  v_diff text;
  v_migration text;
  v_migration_sha text;
  v_rollback_sha text;
  v_plan uuid;
  v_binding jsonb;
  v_action text;
begin
  if p_table_name !~ '^[a-z][a-z0-9_]{0,62}$'
     or length(coalesce(p_idempotency_key,'')) not between 8 and 200 then
    raise exception 'invalid database change request' using errcode='22023';
  end if;

  select * into v_res
  from public.pandora_runtime_resources
  where id=p_runtime_resource_id
    and resource_type='database'
    and provider='supabase'
    and isolation_mode='shared_isolated'
    and status='ready';
  if not found then
    raise exception 'isolated database resource unavailable' using errcode='22023';
  end if;
  if v_res.project_version_id is distinct from p_project_version_id then
    raise exception 'database version lineage mismatch' using errcode='22023';
  end if;
  if v_res.environment not in ('development','preview','production') then
    raise exception 'database environment is outside Tool Gateway contract' using errcode='22023';
  end if;

  v_schema:=v_res.configuration_redacted->>'schema';
  if exists(
    select 1 from information_schema.tables
    where table_schema=v_schema and table_name=p_table_name
  ) then
    raise exception 'database migration identity conflict' using errcode='23505';
  end if;

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
  into v_before
  from information_schema.columns
  where table_schema=v_schema;

  v_migration:='create_table:'||v_schema||'.'||p_table_name||':id_uuid,value_text,created_at_timestamptz';
  v_migration_sha:=encode(extensions.digest(convert_to(v_migration,'utf8'),'sha256'),'hex');

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
  from (
    select table_name,column_name,data_type,is_nullable,ordinal_position
    from information_schema.columns
    where table_schema=v_schema
    union all select p_table_name,'id','uuid','NO',1
    union all select p_table_name,'value','text','NO',2
    union all select p_table_name,'created_at','timestamp with time zone','NO',3
  ) projected;

  v_diff:=encode(
    extensions.digest(convert_to(v_before||':'||v_after,'utf8'),'sha256'),
    'hex'
  );
  v_rollback_sha:=encode(
    extensions.digest(convert_to('drop_table:'||v_schema||'.'||p_table_name,'utf8'),'sha256'),
    'hex'
  );

  select * into v_existing
  from public.pandora_database_change_plans
  where organization_id=v_res.organization_id
    and project_id=v_res.project_id
    and idempotency_key=p_idempotency_key
  for update;

  if found then
    v_plan:=v_existing.id;
  else
    v_plan:=gen_random_uuid();
  end if;

  v_binding:=private.pandora_database_change_request_migration_binding_v1(
    v_plan,
    v_res.organization_id,
    v_res.project_id,
    p_project_version_id,
    v_res.environment,
    p_idempotency_key
  );
  v_action:=v_binding->>'actionHash';

  if v_existing.id is not null then
    if v_existing.project_spec_id<>p_project_spec_id
       or v_existing.project_version_id is distinct from p_project_version_id
       or v_existing.target_runtime_resource_id<>p_runtime_resource_id
       or v_existing.environment<>v_res.environment
       or v_existing.migration_set_sha256<>v_migration_sha
       or v_existing.schema_before_sha256<>v_before
       or v_existing.schema_after_sha256<>v_after
       or v_existing.schema_diff_sha256<>v_diff
       or v_existing.action_hash<>v_action
       or v_existing.rollback_plan_sha256 is distinct from v_rollback_sha
       or v_existing.destructive_change
       or not v_existing.backward_compatible
       or v_existing.lock_risk<>'low'
       or v_existing.approval_required is distinct from (v_res.environment='production') then
      raise exception 'database plan idempotency identity collision' using errcode='23505';
    end if;
  else
    insert into public.pandora_database_change_plans(
      id,organization_id,project_id,project_spec_id,project_version_id,target_runtime_resource_id,
      environment,status,migration_set_sha256,schema_before_sha256,schema_after_sha256,
      schema_diff_sha256,action_hash,destructive_change,backward_compatible,lock_risk,
      approval_required,rollback_plan_sha256,idempotency_key,public_summary
    ) values(
      v_plan,v_res.organization_id,v_res.project_id,p_project_spec_id,p_project_version_id,v_res.id,
      v_res.environment,'reviewed',v_migration_sha,v_before,v_after,v_diff,v_action,false,true,'low',
      (v_res.environment='production'),v_rollback_sha,p_idempotency_key,
      'Add isolated application table '||p_table_name
    );
  end if;

  insert into public.pandora_database_change_items(
    organization_id,project_id,database_change_plan_id,sequence,change_kind,object_type,
    object_name_sha256,destructive,backward_compatible,risk,public_summary
  ) values(
    v_res.organization_id,v_res.project_id,v_plan,1,'create','table',
    encode(extensions.digest(convert_to(v_schema||'.'||p_table_name,'utf8'),'sha256'),'hex'),
    false,true,'low','Create isolated application table'
  ) on conflict do nothing;

  return jsonb_build_object(
    'planId',v_plan,
    'status',(select status from public.pandora_database_change_plans where id=v_plan),
    'migrationSetSha256',v_migration_sha,
    'actionHash',v_action,
    'schemaBeforeSha256',v_before,
    'schemaAfterSha256',v_after,
    'schemaDiffSha256',v_diff,
    'rollbackPlanSha256',v_rollback_sha
  );
end;
$$;

revoke all on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) to service_role;
revoke all on function public.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) to service_role;

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
  v_binding jsonb;
  v_args jsonb;
  v_args_sha text;
  v_action text;
  v_target text;
  v_now timestamptz:=clock_timestamp();
begin
  if p_plan_id is null
     or p_preflight_verification_run_id is null
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
     or v_plan.idempotency_key is distinct from p_idempotency_key then
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

  v_binding:=private.pandora_database_change_request_migration_binding_v1(
    v_plan.id,
    v_plan.organization_id,
    v_plan.project_id,
    v_plan.project_version_id,
    v_plan.environment,
    p_idempotency_key
  );
  v_args:=v_binding->'arguments';
  v_args_sha:=v_binding->>'argumentsSha256';
  v_action:=v_binding->>'actionHash';
  v_target:=v_binding->>'targetResource';

  if v_plan.action_hash is distinct from v_action then
    raise exception 'database plan action binding mismatch' using errcode='22023';
  end if;

  select * into v_tool
  from public.pandora_tool_calls
  where organization_id=v_plan.organization_id
    and action_hash=v_action
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
    ) values(
      v_plan.organization_id,v_plan.project_id,v_plan.project_spec_id,v_plan.project_version_id,
      'request_migration','1','request_migration','preview',v_target,'pandora-tool-policy/1.1.0',
      v_action,v_args_sha,'MEDIUM','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY',
      'REQUIRED',p_idempotency_key,false,'authorized',v_now
    )
    returning * into v_tool;
  end if;

  if v_plan.execution_tool_call_id is not null
     and v_plan.execution_tool_call_id<>v_tool.id then
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
    'environment',v_tool.environment,
    'actionHash',v_action,
    'argumentsSha256',v_args_sha,
    'preflightVerificationRunId',p_preflight_verification_run_id,
    'replayed',v_tool.requested_at<v_now
  );
end;
$$;

revoke all on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role;
revoke all on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_authorize_database_change_execution_v1(uuid,uuid,text) to service_role;
