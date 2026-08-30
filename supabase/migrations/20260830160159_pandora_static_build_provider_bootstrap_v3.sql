create or replace function private.pandora_ensure_static_build_vercel_project_20260830(p_project_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $function$
declare
  v_project public.projectos_projects%rowtype;
  v_journey jsonb;
  v_team text;
  v_name text;
  v_provider jsonb;
  v_body jsonb;
  v_status integer;
  v_provider_id text;
  v_provider_name text;
  v_now timestamptz := clock_timestamp();
begin
  select * into v_project from public.projectos_projects where id=p_project_id for update;
  if not found then raise exception 'STATIC_PROVIDER_PROJECT_NOT_FOUND' using errcode='22023'; end if;

  v_journey:=coalesce(v_project.config->'customerJourney','{}'::jsonb);
  v_provider_id:=coalesce(v_journey->>'vercelProjectId','');
  v_provider_name:=coalesce(v_journey->>'vercelProjectName','');
  if v_provider_id ~ '^prj_[A-Za-z0-9]+$' and v_provider_name<>'' then
    return jsonb_build_object('state','ready','projectId',v_provider_id,'projectName',v_provider_name,'replayed',true);
  end if;

  select config_value into strict v_team
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true;

  v_name:='pandora-' || trim(both '-' from regexp_replace(lower(coalesce(v_project.name,'project')),'[^a-z0-9]+','-','g'));
  v_name:=left(v_name,50) || '-' || left(p_project_id::text,8);
  v_name:=left(v_name,100);

  v_provider:=private.pandora_worker_f_vercel_api_20260829(
    'POST',
    '/v11/projects?teamId='||v_team,
    jsonb_build_object(
      'name',v_name,
      'framework',null,
      'skipGitConnectDuringLink',true,
      'enablePreviewFeedback',true,
      'enableProductionFeedback',true
    )
  );
  v_status:=coalesce((v_provider->>'status')::integer,0);
  v_body:=coalesce(v_provider->'body','{}'::jsonb);

  if v_status=409 or coalesce(v_body->'error'->>'code','') ilike '%conflict%' then
    v_provider:=private.pandora_worker_f_vercel_api_20260829(
      'GET','/v9/projects/'||v_name||'?teamId='||v_team,null
    );
    v_status:=coalesce((v_provider->>'status')::integer,0);
    v_body:=coalesce(v_provider->'body','{}'::jsonb);
  end if;

  if v_status not in (200,201) then
    raise exception 'STATIC_PROVIDER_PROJECT_CREATE_FAILED:%',v_status using errcode='55000';
  end if;

  v_provider_id:=coalesce(v_body->>'id','');
  v_provider_name:=coalesce(v_body->>'name',v_name);
  if v_provider_id !~ '^prj_[A-Za-z0-9]+$' or v_provider_name='' then
    raise exception 'STATIC_PROVIDER_PROJECT_INVALID' using errcode='55000';
  end if;

  update public.projectos_projects
  set config=jsonb_set(
        coalesce(config,'{}'::jsonb),
        '{customerJourney}',
        v_journey || jsonb_build_object(
          'vercelProjectId',v_provider_id,
          'vercelProjectName',v_provider_name,
          'runtimeStatus','ready',
          'runtimeUpdatedAt',v_now
        ),
        true
      ),
      updated_at=v_now
  where id=p_project_id;

  return jsonb_build_object('state','ready','projectId',v_provider_id,'projectName',v_provider_name,'replayed',false);
end
$function$;

revoke all on function private.pandora_ensure_static_build_vercel_project_20260830(uuid) from public,anon,authenticated;
grant execute on function private.pandora_ensure_static_build_vercel_project_20260830(uuid) to service_role;

create or replace function private.pandora_converge_static_builds_tick_20260830()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $function$
declare
  v_job record;
  v_result jsonb;
  v_processed integer := 0;
  v_ready integer := 0;
  v_errors integer := 0;
  v_last_error text := null;
  v_last_sqlstate text := null;
  v_last_job_id uuid := null;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('pandora-static-build-convergence-v1',0)) then
    return jsonb_build_object('state','busy','processed',0,'ready',0,'errors',0);
  end if;

  for v_job in
    select j.id,j.project_id
    from public.pandora_build_jobs j
    join public.pandora_project_versions v
      on v.id=j.target_project_version_id
     and v.organization_id=j.organization_id
     and v.project_id=j.project_id
    where j.job_kind='build'
      and j.status in ('queued','claimed','running','waiting_verification')
      and coalesce(v.source_payload->>'buildAdapter','')='static-web'
    order by j.created_at asc,j.id asc
    limit 5
  loop
    begin
      perform private.pandora_ensure_static_build_vercel_project_20260830(v_job.project_id);
      v_result:=private.pandora_converge_static_site_build_20260830(v_job.id);
      v_processed:=v_processed+1;
      if coalesce(v_result->>'state','')='ready' then v_ready:=v_ready+1; end if;
    exception when others then
      v_processed:=v_processed+1;
      v_errors:=v_errors+1;
      v_last_job_id:=v_job.id;
      v_last_error:=sqlerrm;
      v_last_sqlstate:=sqlstate;
    end;
  end loop;

  return jsonb_build_object('state','ok','processed',v_processed,'ready',v_ready,'errors',v_errors,'lastBuildJobId',v_last_job_id,'lastSqlstate',v_last_sqlstate,'lastError',v_last_error);
end
$function$;