create or replace function private.pandora_validate_build_job_lineage()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_org uuid;
  v_project uuid;
  v_status text;
  v_verified_recovery boolean:=false;
begin
  select s.organization_id,s.project_id into v_org,v_project from public.pandora_project_specs s where s.id=new.project_spec_id;
  if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build job ProjectSpec lineage mismatch' using errcode='23514'; end if;
  if new.source_intent_id is not null then
    select i.organization_id,i.project_id into v_org,v_project from public.pandora_project_intents i where i.id=new.source_intent_id;
    if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build job intent lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.target_project_version_id is not null then
    select v.organization_id,v.project_id into v_org,v_project from public.pandora_project_versions v where v.id=new.target_project_version_id;
    if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build job target project version lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.workflow_run_id is not null then
    select w.organization_id into v_org from public.workflow_runs w where w.id=new.workflow_run_id;
    if v_org is null or v_org<>new.organization_id then raise exception 'build job workflow lineage mismatch' using errcode='23514'; end if;
  end if;
  if new.parent_job_id is not null then
    select j.organization_id,j.project_id into v_org,v_project from public.pandora_build_jobs j where j.id=new.parent_job_id;
    if v_project is null or v_org<>new.organization_id or v_project<>new.project_id then raise exception 'build job parent lineage mismatch' using errcode='23514'; end if;
  end if;

  if tg_op='UPDATE' and new.status is distinct from old.status then
    v_status:=old.status||'>'||new.status;
    if v_status='failed>succeeded' and old.error_code='VERIFICATION_FAILED' and new.target_project_version_id is not null then
      select exists(
        select 1
        from public.pandora_project_versions v
        join public.pandora_verification_runs r on r.id=v.verification_run_id
        where v.id=new.target_project_version_id
          and v.organization_id=new.organization_id
          and v.project_id=new.project_id
          and v.build_job_id=new.id
          and v.lifecycle_status in ('verified','preview_ready','live')
          and r.organization_id=new.organization_id
          and r.project_id=new.project_id
          and r.project_version_id=v.id
          and r.build_job_id=new.id
          and upper(r.status)='PASS'
          and r.required_check_profile='static_site'
          and r.artifact_digest=v.artifact_digest_sha256
          and r.source_digest=v.source_sha256
          and r.builder_identity is distinct from r.verifier_identity
      ) into v_verified_recovery;
    end if;
    if v_status not in (
      'queued>claimed','queued>running','queued>failed','queued>cancelled',
      'claimed>queued','claimed>running','claimed>failed','claimed>cancelled',
      'running>queued','running>waiting_approval','running>waiting_verification','running>succeeded','running>failed','running>cancelled',
      'waiting_approval>queued','waiting_approval>running','waiting_approval>failed','waiting_approval>cancelled',
      'waiting_verification>running','waiting_verification>succeeded','waiting_verification>failed','waiting_verification>cancelled'
    ) and not (v_status='failed>succeeded' and v_verified_recovery) then
      raise exception 'invalid build job state transition %',v_status using errcode='23514';
    end if;
  end if;

  if new.status in ('claimed','running') and (new.lease_owner is null or new.lease_token_sha256 is null or new.lease_expires_at is null) then
    raise exception 'active build job requires lease identity' using errcode='23514';
  end if;
  if tg_op='UPDATE' then
    if new.organization_id<>old.organization_id or new.project_id<>old.project_id or new.project_spec_id<>old.project_spec_id
       or new.source_intent_id is distinct from old.source_intent_id or new.idempotency_key<>old.idempotency_key
       or new.job_kind<>old.job_kind or new.parent_job_id is distinct from old.parent_job_id
       or new.workflow_run_id is distinct from old.workflow_run_id then
      raise exception 'build job identity lineage is immutable' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  if new.status='running' and new.started_at is null then new.started_at:=now(); end if;
  if new.status in ('succeeded','failed','cancelled') and new.completed_at is null then new.completed_at:=now();
  elsif new.status not in ('succeeded','failed','cancelled') then new.completed_at:=null;
  end if;
  return new;
end
$function$;

create or replace function private.pandora_recover_verified_static_build_20260830(p_build_job_id uuid,p_verification_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $function$
declare
  v_job public.pandora_build_jobs%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_run public.pandora_verification_runs%rowtype;
  v_dep public.pandora_project_deployments%rowtype;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_job from public.pandora_build_jobs where id=p_build_job_id for update;
  if not found or v_job.job_kind<>'build' or v_job.status<>'failed' or v_job.error_code<>'VERIFICATION_FAILED' or v_job.target_project_version_id is null then
    raise exception 'VERIFIED_RECOVERY_JOB_INVALID' using errcode='22023';
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_job.target_project_version_id for update;
  if not found or v_ver.build_job_id<>v_job.id or v_ver.verification_run_id<>p_verification_run_id or v_ver.lifecycle_status<>'verified' then
    raise exception 'VERIFIED_RECOVERY_VERSION_INVALID' using errcode='23514';
  end if;
  select * into v_run from public.pandora_verification_runs where id=p_verification_run_id;
  if not found or upper(v_run.status)<>'PASS' or v_run.required_check_profile<>'static_site'
     or v_run.project_version_id<>v_ver.id or v_run.build_job_id<>v_job.id
     or v_run.artifact_digest is distinct from v_ver.artifact_digest_sha256
     or v_run.source_digest is distinct from v_ver.source_sha256
     or v_run.builder_identity is not distinct from v_run.verifier_identity then
    raise exception 'VERIFIED_RECOVERY_PROOF_INVALID' using errcode='23514';
  end if;
  select * into v_dep from public.pandora_project_deployments
   where organization_id=v_job.organization_id and project_id=v_job.project_id and version_id=v_ver.id
     and environment='preview' and provider_deployment_id=v_run.preview_deployment_id
   order by created_at desc limit 1 for update;
  if not found or v_dep.provider_state<>'READY' or v_dep.url is null then
    raise exception 'VERIFIED_RECOVERY_DEPLOYMENT_INVALID' using errcode='23514';
  end if;

  update public.pandora_project_deployments
     set status='ready',verification_state='live_verified',failed_at=null,ready_at=coalesce(ready_at,v_now),last_provider_check_at=v_now,updated_at=v_now
   where id=v_dep.id;
  update public.pandora_runtime_environments
     set status='ready',current_version_id=v_ver.id,current_deployment_id=v_dep.id,verification_state='live_verified',last_reconciled_at=v_now,updated_at=v_now
   where organization_id=v_job.organization_id and project_id=v_job.project_id and environment='preview';
  update public.projectos_projects
     set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||
       jsonb_build_object('stage','preview_ready','runtimeStatus','ready','previewUrl',v_dep.url,'previewProvider',v_dep.provider,
         'previewVersionId',v_ver.id::text,'previewDeploymentId',v_dep.provider_deployment_id,'previewVerificationState','verified','runtimeUpdatedAt',v_now),true),
       updated_at=v_now
   where id=v_job.project_id;
  update public.pandora_build_jobs
     set status='succeeded',current_stage='preview_ready',error_code=null,public_error_summary=null,
         lease_owner=null,lease_token_sha256=null,lease_expires_at=null,completed_at=v_now,heartbeat_at=v_now
   where id=v_job.id;

  return jsonb_build_object('state','ready','buildJobId',v_job.id,'projectVersionId',v_ver.id,'verificationRunId',v_run.id,'previewDeploymentId',v_dep.id,'previewUrl',v_dep.url,'recovered',true);
end
$function$;

revoke all on function private.pandora_recover_verified_static_build_20260830(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_recover_verified_static_build_20260830(uuid,uuid) to service_role;