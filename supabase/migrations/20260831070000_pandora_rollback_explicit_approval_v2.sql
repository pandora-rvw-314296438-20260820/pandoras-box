begin;

-- Production rollback is a consequential action. Worker C must bind the exact
-- action hash to an explicit, durable approval before any runtime mutation.
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
  v_run public.workflow_runs%rowtype;
  v_step public.workflow_steps%rowtype;
  v_approval public.approvals%rowtype;
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
     or v_target.lifecycle_status not in ('verified','preview_ready','live','production_candidate','rolled_back') then
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

  select * into v_run from public.workflow_runs
  where organization_id=p_organization_id and idempotency_key='rollback-approval:'||v_action_hash;
  if not found then
    insert into public.workflow_runs(
      organization_id,workflow_key,workflow_version,status,requester_id,risk_ceiling,
      input_redacted,idempotency_key,budget_cents,started_at
    ) values(
      p_organization_id,'pandora-production-rollback','1','waiting_approval',p_requested_by,'R2',
      jsonb_build_object('projectId',p_project_id,'targetVersionId',p_target_version_id,'expectedProductionVersionId',p_expected_production_version_id,'provider',v_env.provider),
      'rollback-approval:'||v_action_hash,0,now()
    ) returning * into v_run;
  end if;

  select * into v_step from public.workflow_steps
  where run_id=v_run.id and step_key='approve_rollback';
  if not found then
    insert into public.workflow_steps(
      organization_id,run_id,step_key,sequence,tool_name,status,risk,approval_required,idempotency_key,input_redacted
    ) values(
      p_organization_id,v_run.id,'approve_rollback',0,'rollback_project','waiting_approval','R2',true,
      'rollback-step:'||v_action_hash,
      jsonb_build_object('actionHash',v_action_hash,'argumentsSha256',v_args_hash,'targetResource',v_target_resource)
    ) returning * into v_step;
  end if;

  select * into v_approval from public.approvals
  where run_id=v_run.id and step_id=v_step.id and action_hash=v_action_hash
  order by created_at desc limit 1;
  if not found then
    insert into public.approvals(
      organization_id,run_id,step_id,requested_by,assigned_to,decision,action_hash,
      preview_redacted,request_reason,expires_at
    ) values(
      p_organization_id,v_run.id,v_step.id,p_requested_by,p_requested_by,'pending',v_action_hash,
      jsonb_build_object('action','Roll back production','projectId',p_project_id,'fromVersionId',p_expected_production_version_id,'toVersionId',p_target_version_id,'provider',v_env.provider),
      'Production rollback changes the live version and requires explicit owner approval.',now()+interval '30 minutes'
    ) returning * into v_approval;
  end if;

  select * into v_tool_call from public.pandora_tool_calls
  where organization_id=p_organization_id and (action_hash=v_action_hash or (project_id=p_project_id and idempotency_key=trim(p_idempotency_key)))
  limit 1;
  if found then
    if v_tool_call.action_hash<>v_action_hash or v_tool_call.arguments_sha256<>v_args_hash
       or v_tool_call.project_id<>p_project_id or v_tool_call.project_spec_id<>v_target.project_spec_id
       or v_tool_call.project_version_id is distinct from p_target_version_id
       or v_tool_call.tool_name<>'rollback_project' or v_tool_call.tool_version<>'1'
       or v_tool_call.action_name<>'rollback_project' or v_tool_call.environment<>'production'
       or v_tool_call.target_resource_ref<>v_target_resource or v_tool_call.policy_version<>v_policy_version
       or v_tool_call.risk_level<>'HIGH' or v_tool_call.side_effect<>'PRODUCTION_MUTATION'
       or v_tool_call.retry_mode<>'IDEMPOTENT_RETRY' or v_tool_call.idempotency_mode<>'REQUIRED' then
      raise exception 'ROLLBACK_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
    if v_tool_call.approval_required is false and v_tool_call.status in ('authorized','proposed') then
      update public.pandora_tool_calls set decision='REQUIRE_APPROVAL',approval_required=true,approval_id=v_approval.id,status='proposed'
      where id=v_tool_call.id returning * into v_tool_call;
    elsif v_tool_call.approval_id is distinct from v_approval.id then
      raise exception 'ROLLBACK_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
  else
    insert into public.pandora_tool_calls(
      organization_id,project_id,project_spec_id,project_version_id,workflow_run_id,workflow_step_id,
      tool_name,tool_version,action_name,environment,target_resource_ref,policy_version,
      action_hash,arguments_sha256,risk_level,decision,side_effect,retry_mode,
      idempotency_mode,idempotency_key,approval_required,approval_id,status
    ) values(
      p_organization_id,p_project_id,v_target.project_spec_id,p_target_version_id,v_run.id,v_step.id,
      'rollback_project','1','rollback_project','production',v_target_resource,v_policy_version,
      v_action_hash,v_args_hash,'HIGH','REQUIRE_APPROVAL','PRODUCTION_MUTATION','IDEMPOTENT_RETRY',
      'REQUIRED',trim(p_idempotency_key),true,v_approval.id,'proposed'
    ) returning * into v_tool_call;
  end if;

  select * into v_policy from public.pandora_policy_actions
  where organization_id=p_organization_id and action_hash=v_action_hash;
  if found then
    if v_policy.project_id<>p_project_id or v_policy.project_spec_id<>v_target.project_spec_id
       or v_policy.tool_call_id is distinct from v_tool_call.id
       or v_policy.project_version_id is distinct from p_target_version_id
       or v_policy.arguments_sha256<>v_args_hash or v_policy.policy_version<>v_policy_version
       or v_policy.environment<>'production' or v_policy.target_resource_ref<>v_target_resource
       or v_policy.risk_level<>'HIGH' or v_policy.side_effect<>'PRODUCTION_MUTATION' then
      raise exception 'ROLLBACK_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
    if v_policy.approval_required is false and v_policy.status='authorized' then
      update public.pandora_policy_actions
      set disposition='REQUIRE_APPROVAL',approval_required=true,approval_id=v_approval.id,status='proposed',authorized_at=null
      where id=v_policy.id returning * into v_policy;
    elsif v_policy.approval_id is distinct from v_approval.id then
      raise exception 'ROLLBACK_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
  else
    insert into public.pandora_policy_actions(
      organization_id,project_id,project_spec_id,tool_call_id,project_version_id,
      tool_name,tool_version,action_name,action_hash,arguments_sha256,policy_version,
      environment,target_resource_ref,risk_level,disposition,side_effect,
      approval_required,approval_id,status
    ) values(
      p_organization_id,p_project_id,v_target.project_spec_id,v_tool_call.id,p_target_version_id,
      'rollback_project','1','rollback_project',v_action_hash,v_args_hash,v_policy_version,
      'production',v_target_resource,'HIGH','REQUIRE_APPROVAL','PRODUCTION_MUTATION',
      true,v_approval.id,'proposed'
    ) returning * into v_policy;
  end if;

  if v_approval.decision='pending' and v_approval.expires_at>now() then
    return jsonb_build_object(
      'actionHash',v_action_hash,'argumentsSha256',v_args_hash,'authorizationRef',null,
      'decision','REQUIRE_APPROVAL','environment','production','provider',v_env.provider,
      'riskLevel','HIGH','tool','rollback_project@1','toolCallId',v_tool_call.id,
      'approvalId',v_approval.id,'approvalExpiresAt',v_approval.expires_at
    );
  end if;

  if v_approval.decision<>'approved' or v_approval.expires_at<=now() or v_approval.decision_by is null then
    update public.pandora_tool_calls set decision='DENY',status='denied' where id=v_tool_call.id and status<>'succeeded';
    update public.pandora_policy_actions set disposition='DENY',status='denied' where id=v_policy.id and status<>'executed';
    return jsonb_build_object('actionHash',v_action_hash,'decision','DENY','approvalId',v_approval.id,'environment','production','provider',v_env.provider,'riskLevel','HIGH','tool','rollback_project@1');
  end if;

  update public.pandora_tool_calls
  set decision='ALLOW',status='authorized',approval_required=true,approval_id=v_approval.id
  where id=v_tool_call.id returning * into v_tool_call;
  update public.pandora_policy_actions
  set disposition='ALLOW',status='authorized',approval_required=true,approval_id=v_approval.id
  where id=v_policy.id returning * into v_policy;

  return jsonb_build_object(
    'actionHash',v_action_hash,'argumentsSha256',v_args_hash,
    'authorizationRef','worker-c:'||v_action_hash,'decision','ALLOW',
    'environment','production','provider',v_env.provider,'riskLevel','HIGH',
    'tool','rollback_project@1','toolCallId',v_tool_call.id,'approvalId',v_approval.id,
    'approvedBy',v_approval.decision_by
  );
end;
$fn$;

-- Revoke any unexecuted v1 rollback authorizations that were minted without
-- a human approval, so an old receipt cannot bypass the v2 boundary.
update public.pandora_policy_actions
set disposition='DENY',status='revoked'
where tool_name='rollback_project' and tool_version='1' and environment='production'
  and side_effect='PRODUCTION_MUTATION' and approval_required=false and status='authorized' and executed_at is null;
update public.pandora_tool_calls
set decision='DENY',status='cancelled'
where tool_name='rollback_project' and tool_version='1' and environment='production'
  and side_effect='PRODUCTION_MUTATION' and approval_required=false and status='authorized' and completed_at is null;

commit;
