begin;

create or replace function private.pandora_authorize_production_rollback_20260831(
  p_organization_id uuid,
  p_project_id uuid,
  p_target_version_id uuid,
  p_expected_production_version_id uuid,
  p_requested_by uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $fn$
declare
  v_project public.projectos_projects%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_target public.pandora_project_versions%rowtype;
  v_args jsonb;
  v_action jsonb;
  v_args_hash text;
  v_action_hash text;
  v_target_resource text;
  v_tool_call public.pandora_tool_calls%rowtype;
  v_policy public.pandora_policy_actions%rowtype;
  v_policy_version constant text := 'pandora-tool-policy/1.1.0';
begin
  if p_organization_id is null or p_project_id is null or p_target_version_id is null
     or p_expected_production_version_id is null or p_requested_by is null
     or p_target_version_id = p_expected_production_version_id
     or length(trim(coalesce(p_idempotency_key,''))) not between 8 and 200 then
    raise exception 'INVALID_ROLLBACK_REQUEST' using errcode='22023';
  end if;

  select * into v_project
  from public.projectos_projects
  where id=p_project_id and organization_id=p_organization_id and status='active';
  if not found then raise exception 'PROJECT_NOT_FOUND' using errcode='22023'; end if;

  if not exists(
    select 1 from public.memberships
    where organization_id=p_organization_id and user_id=p_requested_by
      and status='active' and role::text='owner'
  ) then
    raise exception 'ROLLBACK_OWNER_REQUIRED' using errcode='42501';
  end if;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=p_organization_id and project_id=p_project_id and environment='production'
  for share;
  if not found
     or v_env.current_version_id is distinct from p_expected_production_version_id
     or v_env.current_deployment_id is null
     or v_env.status<>'ready'
     or v_env.verification_state<>'live_verified' then
    raise exception 'PRODUCTION_PRECONDITION_MISMATCH' using errcode='40001';
  end if;

  select * into v_target
  from public.pandora_project_versions
  where id=p_target_version_id and organization_id=p_organization_id and project_id=p_project_id;
  if not found
     or v_target.project_spec_id is null
     or v_target.build_job_id is null
     or v_target.root_artifact_version_id is null
     or v_target.artifact_digest_sha256 is null
     or v_target.verification_run_id is null
     or v_target.lifecycle_status not in ('verified','preview_ready','live','production_candidate') then
    raise exception 'ROLLBACK_TARGET_NOT_ELIGIBLE' using errcode='22023';
  end if;

  if v_env.provider='supabase_static' then
    if not exists(
      select 1
      from public.pandora_project_deployments d
      join public.pandora_verification_runs r
        on r.id=v_target.verification_run_id
       and r.organization_id=v_target.organization_id
       and r.project_id=v_target.project_id
       and r.project_version_id=v_target.id
       and r.project_spec_id=v_target.project_spec_id
       and r.build_job_id=v_target.build_job_id
       and r.status='PASS'
       and r.target_environment='preview'
       and r.required_check_profile='static_site'
       and r.preview_deployment_id=d.provider_deployment_id
       and r.source_kind=v_target.source_kind
       and r.source_ref=v_target.source_ref
       and r.source_commit is not distinct from v_target.source_commit
       and r.source_digest=v_target.source_sha256
       and r.artifact_digest=v_target.artifact_digest_sha256
      where d.organization_id=p_organization_id and d.project_id=p_project_id
        and d.version_id=p_target_version_id and d.environment='preview'
        and d.provider='supabase_preview' and d.status='ready'
        and d.verification_state='live_verified' and d.provider_state='READY'
    ) then
      raise exception 'ROLLBACK_TARGET_NOT_ELIGIBLE' using errcode='22023';
    end if;
  elsif v_env.provider='vercel' then
    if v_target.rollback_eligible is not true or not exists(
      select 1 from public.pandora_project_deployments d
      where d.organization_id=p_organization_id and d.project_id=p_project_id
        and d.version_id=p_target_version_id and d.environment='production'
        and d.provider='vercel' and d.verification_state='live_verified'
        and d.provider_project_id=v_env.provider_project_id
        and d.provider_deployment_id ~ '^dpl_[A-Za-z0-9]+$'
    ) then
      raise exception 'ROLLBACK_TARGET_NOT_ELIGIBLE' using errcode='22023';
    end if;
  else
    raise exception 'ROLLBACK_PROVIDER_UNSUPPORTED' using errcode='22023';
  end if;

  v_args:=jsonb_build_object(
    'environment','production',
    'expected_production_version_id',p_expected_production_version_id::text,
    'idempotency_key',trim(p_idempotency_key),
    'project_id',p_project_id::text,
    'provider',v_env.provider,
    'target_version_id',p_target_version_id::text
  );
  v_args_hash:=encode(extensions.digest(convert_to(v_args::text,'utf8'),'sha256'),'hex');
  v_target_resource:='production-runtime:'||v_env.id::text;
  v_action:=jsonb_build_object(
    'arguments',v_args,
    'environment','production',
    'organization_id',p_organization_id::text,
    'policy_version',v_policy_version,
    'project_id',p_project_id::text,
    'project_version',p_target_version_id::text,
    'target_resource',v_target_resource,
    'tool','rollback_project',
    'version',1
  );
  v_action_hash:=encode(extensions.digest(convert_to(v_action::text,'utf8'),'sha256'),'hex');

  select * into v_tool_call
  from public.pandora_tool_calls
  where organization_id=p_organization_id
    and (action_hash=v_action_hash or (project_id=p_project_id and idempotency_key=trim(p_idempotency_key)))
  limit 1;

  if found then
    if v_tool_call.action_hash<>v_action_hash
       or v_tool_call.arguments_sha256<>v_args_hash
       or v_tool_call.project_id<>p_project_id
       or v_tool_call.project_spec_id<>v_target.project_spec_id
       or v_tool_call.project_version_id is distinct from p_target_version_id
       or v_tool_call.tool_name<>'rollback_project'
       or v_tool_call.tool_version<>'1'
       or v_tool_call.action_name<>'rollback_project'
       or v_tool_call.environment<>'production'
       or v_tool_call.target_resource_ref<>v_target_resource
       or v_tool_call.policy_version<>v_policy_version
       or v_tool_call.risk_level<>'HIGH'
       or v_tool_call.decision<>'ALLOW'
       or v_tool_call.side_effect<>'PRODUCTION_MUTATION'
       or v_tool_call.retry_mode<>'IDEMPOTENT_RETRY'
       or v_tool_call.idempotency_mode<>'REQUIRED'
       or v_tool_call.approval_required is true
       or v_tool_call.status not in ('authorized','executing','succeeded') then
      raise exception 'ROLLBACK_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
  else
    insert into public.pandora_tool_calls(
      organization_id,project_id,project_spec_id,project_version_id,
      tool_name,tool_version,action_name,environment,target_resource_ref,policy_version,
      action_hash,arguments_sha256,risk_level,decision,side_effect,retry_mode,
      idempotency_mode,idempotency_key,approval_required,status
    ) values(
      p_organization_id,p_project_id,v_target.project_spec_id,p_target_version_id,
      'rollback_project','1','rollback_project','production',v_target_resource,v_policy_version,
      v_action_hash,v_args_hash,'HIGH','ALLOW','PRODUCTION_MUTATION','IDEMPOTENT_RETRY',
      'REQUIRED',trim(p_idempotency_key),false,'authorized'
    ) returning * into v_tool_call;
  end if;

  insert into public.pandora_policy_actions(
    organization_id,project_id,project_spec_id,tool_call_id,project_version_id,
    tool_name,tool_version,action_name,action_hash,arguments_sha256,policy_version,
    environment,target_resource_ref,risk_level,disposition,side_effect,
    approval_required,status
  ) values(
    p_organization_id,p_project_id,v_target.project_spec_id,v_tool_call.id,p_target_version_id,
    'rollback_project','1','rollback_project',v_action_hash,v_args_hash,v_policy_version,
    'production',v_target_resource,'HIGH','ALLOW','PRODUCTION_MUTATION',
    false,'authorized'
  )
  on conflict (organization_id,action_hash) do nothing;

  select * into v_policy
  from public.pandora_policy_actions
  where organization_id=p_organization_id and action_hash=v_action_hash;

  if not found
     or v_policy.project_id<>p_project_id
     or v_policy.project_spec_id<>v_target.project_spec_id
     or v_policy.tool_call_id is distinct from v_tool_call.id
     or v_policy.project_version_id is distinct from p_target_version_id
     or v_policy.arguments_sha256<>v_args_hash
     or v_policy.policy_version<>v_policy_version
     or v_policy.environment<>'production'
     or v_policy.target_resource_ref<>v_target_resource
     or v_policy.risk_level<>'HIGH'
     or v_policy.disposition<>'ALLOW'
     or v_policy.side_effect<>'PRODUCTION_MUTATION'
     or v_policy.approval_required is true
     or v_policy.status not in ('authorized','executed')
     or (v_policy.expires_at is not null and v_policy.expires_at<=now()) then
    raise exception 'ROLLBACK_AUTHORIZATION_POLICY_WRITE_FAILED' using errcode='55000';
  end if;

  return jsonb_build_object(
    'actionHash',v_action_hash,
    'argumentsSha256',v_args_hash,
    'authorizationRef','worker-c:'||v_action_hash,
    'decision','ALLOW',
    'environment','production',
    'provider',v_env.provider,
    'riskLevel','HIGH',
    'tool','rollback_project@1',
    'toolCallId',v_tool_call.id
  );
end;
$fn$;

create or replace function public.pandora_authorize_production_rollback_20260831(
  p_organization_id uuid,
  p_project_id uuid,
  p_target_version_id uuid,
  p_expected_production_version_id uuid,
  p_requested_by uuid,
  p_idempotency_key text
)
returns jsonb
language sql
security definer
set search_path=''
as $fn$
  select private.pandora_authorize_production_rollback_20260831(
    p_organization_id,p_project_id,p_target_version_id,
    p_expected_production_version_id,p_requested_by,p_idempotency_key
  )
$fn$;
revoke all on function public.pandora_authorize_production_rollback_20260831(uuid,uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_authorize_production_rollback_20260831(uuid,uuid,uuid,uuid,uuid,text) to service_role;

create or replace function private.pandora_execute_supabase_static_rollback_20260831(
  p_organization_id uuid,
  p_project_id uuid,
  p_target_version_id uuid,
  p_expected_production_version_id uuid,
  p_requested_by uuid,
  p_idempotency_key text,
  p_action_hash text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $fn$
declare
  v_env public.pandora_runtime_environments%rowtype;
  v_target public.pandora_project_versions%rowtype;
  v_tool public.pandora_tool_calls%rowtype;
  v_policy public.pandora_policy_actions%rowtype;
  v_existing_prod public.pandora_project_deployments%rowtype;
  v_rollback_op public.pandora_runtime_operations%rowtype;
  v_operation_key text;
  v_authorization_ref text;
  v_publish jsonb;
  v_deployment_id uuid;
  v_verify jsonb;
  v_verify_run uuid;
  v_final jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  if p_action_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'ROLLBACK_AUTHORIZATION_REQUIRED' using errcode='42501';
  end if;
  v_authorization_ref:='worker-c:'||p_action_hash;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=p_organization_id and project_id=p_project_id and environment='production'
  for update;
  if not found or v_env.provider<>'supabase_static'
     or v_env.current_version_id is distinct from p_expected_production_version_id
     or v_env.verification_state<>'live_verified' or v_env.status<>'ready' then
    raise exception 'PRODUCTION_PRECONDITION_MISMATCH' using errcode='40001';
  end if;

  select * into v_target
  from public.pandora_project_versions
  where id=p_target_version_id and organization_id=p_organization_id and project_id=p_project_id;
  if not found or v_target.project_spec_id is null then
    raise exception 'ROLLBACK_TARGET_NOT_ELIGIBLE' using errcode='22023';
  end if;

  select * into v_tool
  from public.pandora_tool_calls
  where organization_id=p_organization_id and action_hash=p_action_hash;
  select * into v_policy
  from public.pandora_policy_actions
  where organization_id=p_organization_id and action_hash=p_action_hash;

  if v_tool.id is null or v_policy.id is null
     or v_tool.id<>v_policy.tool_call_id
     or v_tool.project_id<>p_project_id or v_policy.project_id<>p_project_id
     or v_tool.project_spec_id<>v_target.project_spec_id or v_policy.project_spec_id<>v_target.project_spec_id
     or v_tool.project_version_id is distinct from p_target_version_id
     or v_policy.project_version_id is distinct from p_target_version_id
     or v_tool.tool_name<>'rollback_project' or v_tool.tool_version<>'1'
     or v_tool.action_name<>'rollback_project' or v_policy.action_name<>'rollback_project'
     or v_tool.environment<>'production' or v_policy.environment<>'production'
     or v_tool.risk_level<>'HIGH' or v_policy.risk_level<>'HIGH'
     or v_tool.decision<>'ALLOW' or v_policy.disposition<>'ALLOW'
     or v_tool.side_effect<>'PRODUCTION_MUTATION' or v_policy.side_effect<>'PRODUCTION_MUTATION'
     or v_tool.idempotency_key<>trim(p_idempotency_key)
     or v_tool.approval_required is true or v_policy.approval_required is true
     or v_tool.status not in ('authorized','executing','succeeded')
     or v_policy.status not in ('authorized','executed')
     or (v_policy.expires_at is not null and v_policy.expires_at<=now())
     or not exists(
       select 1 from public.memberships
       where organization_id=p_organization_id and user_id=p_requested_by
         and status='active' and role::text='owner'
     ) then
    raise exception 'ROLLBACK_AUTHORIZATION_REQUIRED' using errcode='42501';
  end if;

  v_operation_key:=encode(
    extensions.digest(convert_to(concat_ws('|','supabase-static-rollback-v1',p_organization_id::text,p_project_id::text,p_expected_production_version_id::text,p_target_version_id::text,p_action_hash),'utf8'),'sha256'),
    'hex'
  );

  select * into v_rollback_op
  from public.pandora_runtime_operations
  where provider='supabase_static' and idempotency_key=v_operation_key
  for update;

  if found and v_rollback_op.status='succeeded' then
    return jsonb_build_object(
      'state','live','replayed',true,'provider','supabase_static',
      'projectVersionId',p_target_version_id,
      'authorizationRef',v_authorization_ref,
      'operationId',v_rollback_op.id
    );
  elsif found and v_rollback_op.status in ('claimed','running') then
    return jsonb_build_object('state','working','provider','supabase_static','operationId',v_rollback_op.id);
  elsif found then
    update public.pandora_runtime_operations
    set status='running',ambiguous=false,normalized_error='{}'::jsonb,
        started_at=coalesce(started_at,v_now),finished_at=null,updated_at=v_now
    where id=v_rollback_op.id returning * into v_rollback_op;
  else
    insert into public.pandora_runtime_operations(
      idempotency_key,action,organization_id,project_id,project_version_id,
      environment,provider,authorization_ref,verification_ref,provider_project_id,
      status,started_at
    ) values(
      v_operation_key,'rollback',p_organization_id,p_project_id,p_target_version_id,
      'production','supabase_static',v_authorization_ref,v_target.verification_run_id::text,
      v_env.provider_project_id,'running',v_now
    ) returning * into v_rollback_op;
  end if;

  update public.pandora_tool_calls
  set status='executing',started_at=coalesce(started_at,v_now)
  where id=v_tool.id and status='authorized';

  select * into v_existing_prod
  from public.pandora_project_deployments
  where organization_id=p_organization_id and project_id=p_project_id
    and version_id=p_target_version_id and environment='production'
    and provider='supabase_static' and verification_state='live_verified'
    and status='ready' and provider_state='READY'
  order by created_at desc limit 1;

  if found then
    update public.pandora_runtime_environments
    set current_version_id=p_target_version_id,current_deployment_id=v_existing_prod.id,
        status='ready',verification_state='live_verified',last_reconciled_at=v_now,updated_at=v_now
    where id=v_env.id and current_version_id=p_expected_production_version_id;

    if not found then raise exception 'PRODUCTION_PRECONDITION_MISMATCH' using errcode='40001'; end if;

    update public.pandora_project_versions
    set lifecycle_status='live',rollback_eligible=true,rolled_back_at=null
    where id=p_target_version_id and organization_id=p_organization_id and project_id=p_project_id;

    update public.projectos_projects
    set config=jsonb_set(
      coalesce(config,'{}'::jsonb),
      '{customerJourney}',
      coalesce(config->'customerJourney','{}'::jsonb)||
      jsonb_build_object(
        'stage','live','runtimeStatus','ready','liveUrl',v_existing_prod.url,
        'publishedVersionId',p_target_version_id::text,
        'productionVerificationState','live_verified','runtimeUpdatedAt',v_now
      ),
      true
    ),updated_at=v_now
    where id=p_project_id and organization_id=p_organization_id;

    v_deployment_id:=v_existing_prod.id;
  else
    v_publish:=private.pandora_publish_supabase_fallback_20260831(
      p_project_id,p_target_version_id,p_requested_by,p_expected_production_version_id
    );
    v_deployment_id:=nullif(v_publish->>'deploymentId','')::uuid;
    if v_deployment_id is null then
      raise exception 'ROLLBACK_DEPLOYMENT_FAILED' using errcode='55000';
    end if;

    v_verify:=private.pandora_worker_e_verify_supabase_production_20260831(v_deployment_id,p_requested_by);
    if upper(coalesce(v_verify->>'status',''))<>'PASS' then
      update public.pandora_runtime_operations
      set status='failed',normalized_error=jsonb_build_object('code','ROLLBACK_VERIFICATION_FAILED','verificationRunId',v_verify->>'verificationRunId'),
          finished_at=clock_timestamp(),updated_at=clock_timestamp()
      where id=v_rollback_op.id;
      raise exception 'ROLLBACK_VERIFICATION_FAILED' using errcode='55000';
    end if;
    v_verify_run:=nullif(v_verify->>'verificationRunId','')::uuid;
    if v_verify_run is null then raise exception 'ROLLBACK_VERIFICATION_FAILED' using errcode='55000'; end if;

    v_final:=private.pandora_finalize_verified_production_20260830(v_deployment_id,v_verify_run);
    if coalesce(v_final->>'state','')<>'live' then
      raise exception 'ROLLBACK_FINALIZATION_FAILED' using errcode='55000';
    end if;
  end if;

  update public.pandora_project_deployments
  set authorization_ref=v_authorization_ref
  where id=v_deployment_id and organization_id=p_organization_id and project_id=p_project_id;

  update public.pandora_project_versions
  set lifecycle_status='rolled_back',rolled_back_at=v_now,rollback_eligible=true
  where id=p_expected_production_version_id and organization_id=p_organization_id and project_id=p_project_id;

  update public.pandora_runtime_operations
  set status='succeeded',ambiguous=false,provider_resource_id=(
        select provider_deployment_id from public.pandora_project_deployments where id=v_deployment_id
      ),
      result_facts=jsonb_build_object(
        'rolledBackFromVersionId',p_expected_production_version_id,
        'targetVersionId',p_target_version_id,
        'deploymentId',v_deployment_id,
        'authorizationRef',v_authorization_ref,
        'verificationState','live_verified'
      ),
      finished_at=clock_timestamp(),last_reconciled_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=v_rollback_op.id;

  update public.pandora_tool_calls
  set status='succeeded',completed_at=clock_timestamp()
  where id=v_tool.id and status in ('authorized','executing');
  update public.pandora_policy_actions
  set status='executed'
  where id=v_policy.id and status='authorized';

  return jsonb_build_object(
    'state','live',
    'provider','supabase_static',
    'projectVersionId',p_target_version_id,
    'rolledBackFromVersionId',p_expected_production_version_id,
    'deploymentId',v_deployment_id,
    'authorizationRef',v_authorization_ref,
    'actionHash',p_action_hash,
    'operationId',v_rollback_op.id,
    'verificationState','live_verified'
  );
exception when others then
  if v_rollback_op.id is not null then
    update public.pandora_runtime_operations
    set status='failed',normalized_error=jsonb_build_object('code',sqlstate,'message',left(sqlerrm,300)),
        finished_at=clock_timestamp(),updated_at=clock_timestamp()
    where id=v_rollback_op.id and status<>'succeeded';
  end if;
  if v_tool.id is not null then
    update public.pandora_tool_calls
    set status='failed',error_class='internal',completed_at=clock_timestamp()
    where id=v_tool.id and status='executing';
  end if;
  raise;
end;
$fn$;

create or replace function public.pandora_execute_supabase_static_rollback_20260831(
  p_organization_id uuid,
  p_project_id uuid,
  p_target_version_id uuid,
  p_expected_production_version_id uuid,
  p_requested_by uuid,
  p_idempotency_key text,
  p_action_hash text
)
returns jsonb
language sql
security definer
set search_path=''
as $fn$
  select private.pandora_execute_supabase_static_rollback_20260831(
    p_organization_id,p_project_id,p_target_version_id,
    p_expected_production_version_id,p_requested_by,p_idempotency_key,p_action_hash
  )
$fn$;
revoke all on function public.pandora_execute_supabase_static_rollback_20260831(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_execute_supabase_static_rollback_20260831(uuid,uuid,uuid,uuid,uuid,text,text) to service_role;

commit;
