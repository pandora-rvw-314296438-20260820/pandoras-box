do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_worker_e_verify_supabase_production_20260831';
  if v_def is null then raise exception 'supabase production verifier v1 missing'; end if;
  v_def:=replace(v_def,'supabase-static-production-v1','supabase-static-production-v2');
  v_def:=replace(v_def,'worker-e-supabase-production-verifier-v1','worker-e-supabase-production-verifier-v2');
  execute v_def;
end $$;

do $$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_publish_supabase_fallback_20260831';
  if v_def is null then raise exception 'supabase production publisher v1 missing'; end if;
  v_old:=$block$
  v_verification:=private.pandora_worker_e_verify_supabase_production_20260831(v_prod_id,p_requested_by);
  if upper(coalesce(v_verification->>'status',''))<>'PASS' then
    update public.projectos_projects set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object('stage','needs_attention','runtimeStatus','failed','productionVerificationState','failed','runtimeUpdatedAt',clock_timestamp()),true),updated_at=clock_timestamp() where id=p_project_id;
    return jsonb_build_object('deploymentId',v_prod_id,'projectVersionId',p_version_id,'verificationRunId',v_verification->>'verificationRunId','state','blocked','stage','production_verification','provider','supabase_static');
  end if;
  v_run_id:=(v_verification->>'verificationRunId')::uuid;
  v_final:=private.pandora_finalize_verified_production_20260830(v_prod_id,v_run_id);
  return v_final||jsonb_build_object('provider','supabase_static');
$block$;
  v_new:=$block$
  return jsonb_build_object('deploymentId',v_prod_id,'projectVersionId',p_version_id,'state','working','stage','production_verification','provider','supabase_static','verificationState','ready_for_verification');
$block$;
  if position(v_old in v_def)=0 then raise exception 'publisher verification block not found'; end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end $$;

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
    return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state','live','replayed',true,'provider',v_dep.provider);
  end if;
  if v_dep.verification_state<>'ready_for_verification' then
    return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state',v_dep.verification_state,'provider',v_dep.provider);
  end if;

  select exists(select 1 from public.pandora_project_domains where organization_id=v_dep.organization_id and project_id=v_dep.project_id and environment='production' and primary_domain=true) into v_domain_exists;
  if v_domain_exists and v_dep.provider='vercel' then
    v_domain_ready:=private.pandora_refresh_primary_production_domain_20260830(v_dep.organization_id,v_dep.project_id);
    if not v_domain_ready then
      return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'state','working','stage','domain','provider',v_dep.provider);
    end if;
  end if;

  select j.* into v_job from public.pandora_project_versions v join public.pandora_build_jobs j on j.id=v.build_job_id where v.id=v_dep.version_id;
  if not found then raise exception 'PRODUCTION_BUILD_JOB_REQUIRED' using errcode='22023'; end if;

  if v_dep.provider='supabase_static' then
    v_verification:=private.pandora_worker_e_verify_supabase_production_20260831(v_dep.id,v_job.requested_by);
  elsif v_dep.provider='vercel' then
    v_verification:=private.pandora_worker_e_verify_runtime_20260829(v_dep.id,'production_release',v_job.requested_by);
  else
    raise exception 'PRODUCTION_PROVIDER_UNSUPPORTED' using errcode='22023';
  end if;

  if upper(coalesce(v_verification->>'status',''))='PASS' then
    v_run_id:=(v_verification->>'verificationRunId')::uuid;
    return private.pandora_finalize_verified_production_20260830(v_dep.id,v_run_id)||jsonb_build_object('provider',v_dep.provider);
  end if;
  update public.projectos_projects
     set config=jsonb_set(coalesce(config,'{}'::jsonb),'{customerJourney}',coalesce(config->'customerJourney','{}'::jsonb)||jsonb_build_object(
       'stage','needs_attention','runtimeStatus','failed','productionVerificationState','failed','runtimeUpdatedAt',clock_timestamp()
     ),true),updated_at=clock_timestamp()
   where id=v_dep.project_id and organization_id=v_dep.organization_id;
  return jsonb_build_object('deploymentId',v_dep.id,'projectVersionId',v_dep.version_id,'verificationRunId',v_verification->>'verificationRunId','state','blocked','stage','production_verification','provider',v_dep.provider);
end;
$$;

revoke all on function private.pandora_converge_production_release_20260830(uuid) from public,anon,authenticated;
grant execute on function private.pandora_converge_production_release_20260830(uuid) to service_role;

create or replace function public.pandora_converge_production_release_20260830(p_deployment_id uuid)
returns jsonb
language sql
security definer
set search_path=''
as $$ select private.pandora_converge_production_release_20260830(p_deployment_id); $$;
revoke all on function public.pandora_converge_production_release_20260830(uuid) from public,anon,authenticated;
grant execute on function public.pandora_converge_production_release_20260830(uuid) to service_role;