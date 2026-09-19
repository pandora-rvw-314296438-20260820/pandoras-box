-- Pandora production-release convergence v1.
-- Publish promotion remains a production candidate until independent Worker E proof passes.
-- Provider credentials remain Vault-backed in the existing Worker F / Worker E primitives.

create or replace function private.pandora_refresh_primary_production_domain_20260830(
  p_organization_id uuid,
  p_project_id uuid
)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $$
declare
  v_domain public.pandora_project_domains%rowtype;
  v_team text;
  v_project jsonb;
  v_config jsonb;
  v_project_body jsonb;
  v_config_body jsonb;
  v_http extensions.http_response;
  v_ownership boolean:=false;
  v_dns boolean:=false;
  v_tls boolean:=false;
  v_routing boolean:=false;
  v_runtime boolean:=false;
  v_ready boolean:=false;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_domain
  from public.pandora_project_domains
  where organization_id=p_organization_id and project_id=p_project_id
    and environment='production' and primary_domain=true
  order by updated_at desc limit 1;
  if not found then return true; end if;

  select config_value into strict v_team
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true;

  v_project:=private.pandora_worker_f_vercel_api_20260829(
    'GET','/v9/projects/'||v_domain.provider_project_id||'/domains/'||v_domain.domain||'?teamId='||v_team,null
  );
  v_config:=private.pandora_worker_f_vercel_api_20260829(
    'GET','/v6/domains/'||v_domain.domain||'/config?teamId='||v_team,null
  );
  if coalesce((v_project->>'status')::integer,0)=200 then
    v_project_body:=coalesce(v_project->'body','{}'::jsonb);
    v_ownership:=coalesce((v_project_body->>'verified')::boolean,false);
  end if;
  if coalesce((v_config->>'status')::integer,0)=200 then
    v_config_body:=coalesce(v_config->'body','{}'::jsonb);
    v_dns:=coalesce((v_config_body->>'misconfigured')::boolean,true)=false;
  end if;

  begin
    select * into v_http from extensions.http((
      'GET'::extensions.http_method,
      ('https://'||v_domain.domain||'/')::varchar,
      array[
        extensions.http_header('user-agent','Pandora-Worker-F-Domain-Probe/1.0'),
        extensions.http_header('cache-control','no-store')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    v_tls:=true;
    v_runtime:=v_http.status between 200 and 399;
    v_routing:=v_runtime and exists(
      select 1 from unnest(v_http.headers) h where lower(h.field)='x-vercel-id'
    );
  exception when others then
    v_tls:=false; v_runtime:=false; v_routing:=false;
  end;

  v_ready:=v_ownership and v_dns and v_tls and v_routing and v_runtime;
  update public.pandora_project_domains
     set ownership_verified=v_ownership,dns_configured=v_dns,tls_ready=v_tls,
         routing_ready=v_routing,runtime_healthy=v_runtime,verified=v_ready,
         status=case when v_ready then 'ready'
                     when not v_ownership then 'verification_required'
                     when not v_dns then 'dns_pending'
                     when not v_tls then 'tls_pending'
                     when not v_routing then 'routing_pending'
                     else 'unhealthy' end,
         last_checked_at=v_now,updated_at=v_now
   where id=v_domain.id;
  return v_ready;
end;
$$;
revoke all on function private.pandora_refresh_primary_production_domain_20260830(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_refresh_primary_production_domain_20260830(uuid,uuid) to service_role;

create or replace function private.pandora_finalize_verified_production_20260830(
  p_deployment_id uuid,
  p_verification_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_run public.pandora_verification_runs%rowtype;
  v_project public.projectos_projects%rowtype;
  v_domain public.pandora_project_domains%rowtype;
  v_domain_ready boolean:=false;
  v_live_url text;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep from public.pandora_project_deployments
   where id=p_deployment_id and environment='production' for update;
  if not found then raise exception 'PRODUCTION_DEPLOYMENT_REQUIRED' using errcode='22023'; end if;
  if v_dep.verification_state='live_verified' then
    select * into v_project from public.projectos_projects where id=v_dep.project_id;
    return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state','live','liveUrl',v_project.config->'customerJourney'->>'liveUrl','replayed',true);
  end if;
  if v_dep.verification_state<>'ready_for_verification' then
    raise exception 'PRODUCTION_VERIFICATION_STATE_INVALID' using errcode='40001';
  end if;

  select * into v_env from public.pandora_runtime_environments
   where organization_id=v_dep.organization_id and project_id=v_dep.project_id and environment='production'
     and current_deployment_id=v_dep.id and current_version_id=v_dep.version_id for update;
  if not found or v_env.verification_state<>'ready_for_verification' then
    raise exception 'PRODUCTION_ENVIRONMENT_PRECONDITION_MISMATCH' using errcode='40001';
  end if;
  select * into v_ver from public.pandora_project_versions
   where id=v_dep.version_id and organization_id=v_dep.organization_id and project_id=v_dep.project_id for update;
  if not found or v_ver.lifecycle_status<>'production_candidate' then
    raise exception 'PRODUCTION_VERSION_PRECONDITION_MISMATCH' using errcode='40001';
  end if;
  select * into v_run from public.pandora_verification_runs
   where id=p_verification_run_id and organization_id=v_dep.organization_id and project_id=v_dep.project_id
     and project_version_id=v_ver.id and build_job_id=v_ver.build_job_id;
  if not found or upper(v_run.status)<>'PASS' or v_run.target_environment<>'production'
     or v_run.required_check_profile<>'production_release'
     or v_run.project_spec_id<>v_ver.project_spec_id
     or v_run.source_kind<>v_ver.source_kind
     or v_run.source_ref<>v_ver.source_ref
     or v_run.source_commit is distinct from v_ver.source_commit
     or v_run.source_digest<>v_ver.source_sha256
     or v_run.artifact_digest<>v_ver.artifact_digest_sha256
     or v_run.migration_set_digest is distinct from v_ver.migration_set_digest_sha256
     or v_run.runtime_target_digest is distinct from v_ver.runtime_target_digest_sha256
     or v_run.preview_deployment_id<>v_dep.provider_deployment_id
     or v_run.completed_at is null or v_run.completed_at<v_dep.created_at then
    raise exception 'PRODUCTION_VERIFICATION_IDENTITY_MISMATCH' using errcode='23514';
  end if;

  select * into v_domain from public.pandora_project_domains
   where organization_id=v_dep.organization_id and project_id=v_dep.project_id
     and environment='production' and primary_domain=true order by updated_at desc limit 1;
  if found then
    v_domain_ready:=v_domain.ownership_verified and v_domain.dns_configured and v_domain.tls_ready and v_domain.routing_ready and v_domain.runtime_healthy;
  end if;
  v_live_url:=case when v_domain_ready then 'https://'||v_domain.domain else v_dep.url end;

  update public.pandora_project_deployments
     set verification_state='live_verified',verification_ref=p_verification_run_id::text,
         status='ready',last_provider_check_at=v_now,updated_at=v_now
   where id=v_dep.id and verification_state='ready_for_verification';
  if not found then raise exception 'PRODUCTION_DEPLOYMENT_RACE' using errcode='40001'; end if;
  update public.pandora_runtime_environments
     set verification_state='live_verified',status='ready',last_reconciled_at=v_now,updated_at=v_now
   where id=v_env.id and current_deployment_id=v_dep.id and current_version_id=v_ver.id and verification_state='ready_for_verification';
  if not found then raise exception 'PRODUCTION_ENVIRONMENT_RACE' using errcode='40001'; end if;
  update public.pandora_project_versions
     set lifecycle_status='live',rollback_eligible=true,verification_run_id=p_verification_run_id
   where id=v_ver.id and lifecycle_status='production_candidate';
  if not found then raise exception 'PRODUCTION_VERSION_RACE' using errcode='40001'; end if;

  select * into v_project from public.projectos_projects where id=v_dep.project_id for update;
  update public.projectos_projects
     set config=jsonb_set(coalesce(v_project.config,'{}'::jsonb),'{customerJourney}',
       coalesce(v_project.config->'customerJourney','{}'::jsonb)||jsonb_build_object(
         'stage','live','runtimeStatus','ready','liveUrl',v_live_url,'productionCandidateUrl',null,
         'productionVerificationState','live_verified','productionVerificationRunId',p_verification_run_id::text,
         'publishedVersionId',v_ver.id::text,'runtimeUpdatedAt',v_now
       ),true),updated_at=v_now
   where id=v_dep.project_id and organization_id=v_dep.organization_id;

  return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_ver.id,'verificationRunId',p_verification_run_id,'state','live','liveUrl',v_live_url,'replayed',false);
end;
$$;
revoke all on function private.pandora_finalize_verified_production_20260830(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_finalize_verified_production_20260830(uuid,uuid) to service_role;

create or replace function private.pandora_converge_production_release_20260830(p_deployment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_domain_exists boolean:=false;
  v_domain_ready boolean:=true;
  v_verification jsonb;
  v_run_id uuid;
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id and environment='production';
  if not found then raise exception 'PRODUCTION_DEPLOYMENT_REQUIRED' using errcode='22023'; end if;
  if v_dep.verification_state='live_verified' then
    return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state','live','replayed',true);
  end if;
  if v_dep.verification_state<>'ready_for_verification' then
    return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state',v_dep.verification_state);
  end if;
  select exists(select 1 from public.pandora_project_domains where organization_id=v_dep.organization_id and project_id=v_dep.project_id and environment='production' and primary_domain=true) into v_domain_exists;
  if v_domain_exists then
    v_domain_ready:=private.pandora_refresh_primary_production_domain_20260830(v_dep.organization_id,v_dep.project_id);
    if not v_domain_ready then
      return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state','working','stage','domain');
    end if;
  end if;
  select j.* into v_job from public.pandora_project_versions v join public.pandora_build_jobs j on j.id=v.build_job_id where v.id=v_dep.version_id;
  if not found then raise exception 'PRODUCTION_BUILD_JOB_REQUIRED' using errcode='22023'; end if;

  v_verification:=private.pandora_worker_e_verify_runtime_20260829(v_dep.id,'production_release',v_job.requested_by);
  if upper(coalesce(v_verification->>'status',''))='PASS' then
    v_run_id:=(v_verification->>'verificationRunId')::uuid;
    return private.pandora_finalize_verified_production_20260830(v_dep.id,v_run_id);
  end if;
  update public.projectos_projects
     set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object(
       'stage','needs_attention','runtimeStatus','failed','productionVerificationState','failed','runtimeUpdatedAt',clock_timestamp()
     ),true),updated_at=clock_timestamp()
   where id=v_dep.project_id and organization_id=v_dep.organization_id;
  return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'verificationRunId',v_verification->>'verificationRunId','state','blocked','stage','production_verification');
end;
$$;
revoke all on function private.pandora_converge_production_release_20260830(uuid) from public,anon,authenticated;
grant execute on function private.pandora_converge_production_release_20260830(uuid) to service_role;

create or replace function public.pandora_converge_production_release_20260830(p_deployment_id uuid)
returns jsonb language sql security definer set search_path=''
as $$ select private.pandora_converge_production_release_20260830($1); $$;
revoke all on function public.pandora_converge_production_release_20260830(uuid) from public,anon,authenticated;
grant execute on function public.pandora_converge_production_release_20260830(uuid) to service_role;

create or replace function private.pandora_converge_pending_production_releases_20260830(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit,5),20));
  v_dep record;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
begin
  for v_dep in
    select d.id from public.pandora_runtime_environments e
    join public.pandora_project_deployments d on d.id=e.current_deployment_id
    where e.environment='production' and e.verification_state='ready_for_verification'
      and d.environment='production' and d.verification_state='ready_for_verification'
    order by d.created_at limit v_limit
  loop
    begin
      v_result:=private.pandora_converge_production_release_20260830(v_dep.id);
      v_results:=v_results||jsonb_build_array(v_result);
    exception when others then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('deploymentId',v_dep.id,'state','retry'));
    end;
  end loop;
  return jsonb_build_object('processed',jsonb_array_length(v_results),'results',v_results,'checkedAt',clock_timestamp());
end;
$$;
revoke all on function private.pandora_converge_pending_production_releases_20260830(integer) from public,anon,authenticated;
grant execute on function private.pandora_converge_pending_production_releases_20260830(integer) to service_role;

create or replace function public.pandora_converge_pending_production_releases_20260830(p_limit integer default 5)
returns jsonb language sql security definer set search_path=''
as $$ select private.pandora_converge_pending_production_releases_20260830($1); $$;
revoke all on function public.pandora_converge_pending_production_releases_20260830(integer) from public,anon,authenticated;
grant execute on function public.pandora_converge_pending_production_releases_20260830(integer) to service_role;

do $cron$
declare v_jobid bigint;
begin
  if to_regnamespace('cron') is null then return; end if;
  for v_jobid in execute 'select jobid from cron.job where jobname=''pandora-production-release-convergence''' loop
    execute format('select cron.unschedule(%s)',v_jobid);
  end loop;
  execute 'select cron.schedule(''pandora-production-release-convergence'',''* * * * *'',''select private.pandora_converge_pending_production_releases_20260830(5);'')';
end
$cron$;
