begin;

create or replace function private.pandora_static_preview_acceptance_v4(
  p_runtime_body text,
  p_project_name text,
  p_business_summary text,
  p_acceptance_scope jsonb
)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_body text:=coalesce(p_runtime_body,'');
  v_body_lower text:=lower(coalesce(p_runtime_body,''));
  v_identity text;
  v_title text;
  v_h1 text;
  v_title_text text;
  v_h1_text text;
  v_generic boolean:=false;
  v_link text;
  v_fn text;
begin
  if length(v_body)<128
     or position('<html' in v_body_lower)=0
     or position('<body' in v_body_lower)=0
     or jsonb_typeof(p_acceptance_scope->'functional')<>'array'
     or jsonb_array_length(p_acceptance_scope->'functional')=0 then
    return false;
  end if;

  if v_body_lower ~ '(404[[:space:]]+not[[:space:]]+found|application[[:space:]]+error|internal[[:space:]]+server[[:space:]]+error|service[[:space:]]+unavailable)' then
    return false;
  end if;

  v_identity:=lower(trim(regexp_replace(
    coalesce(p_project_name,''),
    '[[:space:]]+(landing[[:space:]]+page|landing|website|web[[:space:]]*site|site|page|app|application|project)[[:space:]]*$',
    '',
    'i'
  )));

  v_generic :=
    length(v_identity)<3
    or v_identity in (
      'decoration','decor','design','redesign','ui','ux','frontend','front end',
      'homepage','home page','website','site','page','landing','landing page',
      'app','application','project','fix','repair','update','improvement','enhancement'
    );

  if not v_generic then
    if position(v_identity in v_body_lower)=0 then
      return false;
    end if;
  else
    v_title:=substring(v_body from '(?is)<title[^>]*>(.*?)</title>');
    v_h1:=substring(v_body from '(?is)<h1[^>]*>(.*?)</h1>');
    v_title_text:=trim(regexp_replace(coalesce(v_title,''),'<[^>]+>',' ','g'));
    v_h1_text:=trim(regexp_replace(coalesce(v_h1,''),'<[^>]+>',' ','g'));
    if length(regexp_replace(v_title_text,'[[:space:]]+','','g'))<3
       and length(regexp_replace(v_h1_text,'[[:space:]]+','','g'))<3 then
      return false;
    end if;
  end if;

  for v_link in
    select distinct m[1]
    from regexp_matches(v_body,'href=["'']#([^"'']+)["'']','g') m
  loop
    if nullif(v_link,'') is not null
       and position('id="'||v_link||'"' in v_body)=0
       and position('id='''||v_link||'''' in v_body)=0 then
      return false;
    end if;
  end loop;

  for v_fn in
    select distinct m[1]
    from regexp_matches(v_body,'onclick=["''][[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*\(','g') m
  loop
    if lower(v_fn) in ('window','document','location','history','console','alert','confirm','prompt','settimeout','setinterval') then
      continue;
    end if;
    if position('function '||lower(v_fn)||'(' in v_body_lower)=0
       and position('function '||lower(v_fn)||' (' in v_body_lower)=0
       and position('const '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0
       and position('let '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0
       and position('var '||lower(v_fn)||'=' in replace(v_body_lower,' ',''))=0 then
      return false;
    end if;
  end loop;

  return true;
end
$function$;

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid)'::regprocedure
  ) into v_def;

  if position('pandora_static_preview_acceptance_v4' in v_def)=0 then
    if position('pandora_static_preview_acceptance_v3' in v_def)=0 then
      raise exception 'SUPABASE_ACCEPTANCE_V4_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,'pandora_static_preview_acceptance_v3','pandora_static_preview_acceptance_v4');
  end if;

  if position('static_site_acceptance_v4' in v_def)=0 then
    if position('static_site_acceptance_v3' in v_def)=0 then
      raise exception 'SUPABASE_ACCEPTANCE_V4_IDENTITY_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,'static_site_acceptance_v3','static_site_acceptance_v4');
  end if;

  execute v_def;
end
$migration$;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid)'::regprocedure
  ) into v_def;

  v_old :=
    '    where name in (''mcpmaster_supabase_account_1_pat'',''mcpmaster_supabase_account_2_pat'')'||chr(10)||
    '    order by case name when ''mcpmaster_supabase_account_1_pat'' then 1 else 2 end';
  v_new :=
    '    where name in (''Supabase_access'',''mcpmaster_supabase_account_1_pat'',''mcpmaster_supabase_account_2_pat'')'||chr(10)||
    '    order by case name when ''Supabase_access'' then 0 when ''mcpmaster_supabase_account_1_pat'' then 1 else 2 end';
  if position('Supabase_access' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'VERCEL_SUPABASE_ACCESS_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old :=
    '  v_acceptance_ok:=v_runtime_ok and jsonb_typeof(v_spec.acceptance_scope->''functional'')=''array'' and jsonb_array_length(v_spec.acceptance_scope->''functional'')>0;'||chr(10)||
    '  if v_acceptance_ok and nullif(v_spec.business_summary,'''') is not null then'||chr(10)||
    '    v_acceptance_ok:=position(lower(left(v_spec.business_summary,80)) in lower(v_runtime_body))>0 or position(lower(left((select name from public.projectos_projects where id=v_ver.project_id),80)) in lower(v_runtime_body))>0;'||chr(10)||
    '  end if;';
  v_new :=
    '  v_acceptance_ok:=v_runtime_ok and private.pandora_static_preview_acceptance_v4('||chr(10)||
    '    v_runtime_body,'||chr(10)||
    '    (select name from public.projectos_projects where id=v_ver.project_id),'||chr(10)||
    '    v_spec.business_summary,'||chr(10)||
    '    v_spec.acceptance_scope'||chr(10)||
    '  );';
  if position('pandora_static_preview_acceptance_v4' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'VERCEL_ACCEPTANCE_V4_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  v_old := 'concat_ws(''|'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,v_profile,v_ver.source_sha256';
  v_new := 'concat_ws(''|'',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,case when v_profile=''static_site'' then ''static_site_acceptance_v4'' else ''production_release_acceptance_v4'' end,v_ver.source_sha256';
  if position('static_site_acceptance_v4' in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'VERCEL_ACCEPTANCE_V4_IDENTITY_ANCHOR_MISSING' using errcode='55000';
    end if;
    v_def:=replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end
$migration$;

create or replace function private.pandora_retry_failed_vercel_preview_verification_20260906(
  p_deployment_id uuid,
  p_requested_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_env public.pandora_runtime_environments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_previous_run public.pandora_verification_runs%rowtype;
  v_result jsonb;
  v_run_id uuid;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep
  from public.pandora_project_deployments
  where id=p_deployment_id
  for update;

  if not found
     or v_dep.environment<>'preview'
     or v_dep.provider<>'vercel'
     or v_dep.provider_state<>'READY'
     or v_dep.status not in ('ready_for_verification','failed')
     or v_dep.verification_state not in ('ready_for_verification','failed')
     or v_dep.provider_deployment_id is null
     or v_dep.url is null then
    raise exception 'VERCEL_PREVIEW_VERIFICATION_RETRY_DEPLOYMENT_INVALID' using errcode='22023';
  end if;

  select * into v_env
  from public.pandora_runtime_environments
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and environment='preview'
    and current_deployment_id=v_dep.id
    and current_version_id=v_dep.version_id
  for update;
  if not found then
    raise exception 'VERCEL_PREVIEW_VERIFICATION_RETRY_ENVIRONMENT_INVALID' using errcode='40001';
  end if;

  select * into v_ver
  from public.pandora_project_versions
  where id=v_dep.version_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
  for update;
  if not found
     or v_ver.build_job_id is null
     or v_ver.lifecycle_status not in ('verification_pending','verified') then
    raise exception 'VERCEL_PREVIEW_VERIFICATION_RETRY_VERSION_INVALID' using errcode='22023';
  end if;

  select * into v_job
  from public.pandora_build_jobs
  where id=v_ver.build_job_id
    and organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
  for update;
  if not found
     or v_job.status<>'failed'
     or v_job.error_code<>'VERIFICATION_FAILED'
     or v_job.target_project_version_id<>v_ver.id then
    raise exception 'VERCEL_PREVIEW_VERIFICATION_RETRY_BUILD_INVALID' using errcode='22023';
  end if;

  select * into v_previous_run
  from public.pandora_verification_runs
  where organization_id=v_dep.organization_id
    and project_id=v_dep.project_id
    and project_version_id=v_ver.id
    and build_job_id=v_job.id
    and preview_deployment_id=v_dep.provider_deployment_id
    and target_environment='preview'
    and required_check_profile='static_site'
    and status='FAIL'
  order by completed_at desc nulls last,created_at desc
  limit 1;
  if not found then
    raise exception 'VERCEL_PREVIEW_VERIFICATION_RETRY_FAILED_PROOF_MISSING' using errcode='23514';
  end if;

  update public.pandora_project_deployments
  set status='ready_for_verification',
      verification_state='ready_for_verification',
      failed_at=null,
      last_provider_check_at=v_now,
      updated_at=v_now
  where id=v_dep.id;

  update public.pandora_runtime_environments
  set verification_state='ready_for_verification',
      last_reconciled_at=v_now,
      updated_at=v_now
  where id=v_env.id;

  v_result:=private.pandora_worker_e_verify_runtime_20260829(
    v_dep.id,
    'static_site',
    coalesce(p_requested_by,v_job.requested_by)
  );

  if upper(coalesce(v_result->>'status',''))<>'PASS' then
    update public.pandora_project_deployments
    set status='failed',
        verification_state='failed',
        failed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=v_dep.id;
    return jsonb_build_object(
      'state','blocked',
      'stage','verification',
      'deploymentId',v_dep.id,
      'verificationRunId',v_result->>'verificationRunId',
      'previousVerificationRunId',v_previous_run.id
    );
  end if;

  v_run_id:=(v_result->>'verificationRunId')::uuid;
  return private.pandora_recover_verified_static_build_20260830(
    v_job.id,
    v_run_id
  ) || jsonb_build_object(
    'retried',true,
    'provider','vercel',
    'previousVerificationRunId',v_previous_run.id
  );
end
$function$;

revoke all on function private.pandora_retry_failed_vercel_preview_verification_20260906(uuid,uuid)
from public,anon,authenticated;
grant execute on function private.pandora_retry_failed_vercel_preview_verification_20260906(uuid,uuid)
to service_role;

comment on function private.pandora_static_preview_acceptance_v4(text,text,text,jsonb) is
'Observable static-page acceptance v4. Generic working names use substantive title/H1 identity while non-generic names must remain visibly represented; internal links and click handlers remain fail-closed.';
comment on function private.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid) is
'Vercel runtime verifier prefers Supabase_access and uses observable static acceptance v4 with replay-safe identities.';
comment on function private.pandora_retry_failed_vercel_preview_verification_20260906(uuid,uuid) is
'Reopens only the exact current Vercel preview failed by VERIFICATION_FAILED and recovers the build only after a fresh Worker E PASS.';

commit;
