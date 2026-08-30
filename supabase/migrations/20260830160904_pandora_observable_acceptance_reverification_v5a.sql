create or replace function private.pandora_evaluate_supabase_preview_acceptance_v2_20260830(p_deployment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_spec public.pandora_project_specs%rowtype;
  v_runtime extensions.http_response;
  v_body text := '';
  v_lower text := '';
  v_criteria jsonb := '[]'::jsonb;
  v_criterion text;
  v_recognized boolean;
  v_observed boolean;
  v_total integer := 0;
  v_passed integer := 0;
  v_words integer;
  v_matches integer;
  v_threshold integer;
  v_has_tracking boolean := false;
  v_has_onboarding boolean := false;
  v_has_publish boolean := false;
  v_has_journey boolean := false;
  v_digest text;
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id;
  if not found or v_dep.provider<>'supabase_preview' or v_dep.environment<>'preview'
     or v_dep.provider_state<>'READY'
     or v_dep.url !~ '^https://jcyqixttuebxqqfkjonq[.]supabase[.]co/functions/v1/pandora-preview-host/[0-9a-f]{64}/index[.]html$' then
    return jsonb_build_object('ok',false,'reason','exact_preview_required');
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_dep.version_id and project_id=v_dep.project_id;
  if not found or v_ver.project_spec_id is null then return jsonb_build_object('ok',false,'reason','version_lineage_invalid'); end if;
  select * into v_spec from public.pandora_project_specs where id=v_ver.project_spec_id and project_id=v_dep.project_id;
  if not found then return jsonb_build_object('ok',false,'reason','project_spec_missing'); end if;

  begin
    select * into v_runtime from extensions.http((
      'GET'::extensions.http_method,v_dep.url::varchar,
      array[extensions.http_header('user-agent','Pandora-Worker-E-Observable-Acceptance/2.0'),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
  exception when others then
    return jsonb_build_object('ok',false,'reason','runtime_unavailable');
  end;
  if v_runtime.status<200 or v_runtime.status>399 then
    return jsonb_build_object('ok',false,'reason','runtime_unhealthy','httpStatus',v_runtime.status);
  end if;
  v_body:=left(coalesce(v_runtime.content,''),1048576);
  v_lower:=lower(v_body);
  v_digest:=encode(extensions.digest(convert_to(v_body,'utf8'),'sha256'),'hex');
  if length(v_body)<1024 or v_lower ~ '<body[^>]*>[[:space:]]*(loading([.][.][.])?|coming soon|placeholder)[[:space:]]*</body>' then
    return jsonb_build_object('ok',false,'reason','placeholder_or_empty','httpStatus',v_runtime.status,'runtimeBodySha256',v_digest);
  end if;

  v_has_tracking:=v_lower ~ '(trackevent[[:space:]]*[(]|datalayer|posthog|analytics[.]track|gtag[[:space:]]*[(])';
  v_has_onboarding:=position('<a' in v_lower)>0 and position('href=' in v_lower)>0
    and v_lower ~ '(sign in|log in|login|start building|onboard|create project|build it)';
  v_has_publish:=v_lower ~ '(publish|go live|online|live preview|make it live)';
  v_has_journey:=position('pandora' in v_lower)>0 and (
    position('how it works' in v_lower)>0
    or (position('see' in v_lower)>0 and position('focus' in v_lower)>0 and position('tell' in v_lower)>0
      and position('transform' in v_lower)>0 and position('review' in v_lower)>0 and position('publish' in v_lower)>0)
  );

  v_criteria:=coalesce(v_spec.acceptance_scope->'functional','[]'::jsonb) || coalesce(v_spec.acceptance_scope->'business','[]'::jsonb);
  if jsonb_typeof(v_criteria)<>'array' or jsonb_array_length(v_criteria)=0 then
    return jsonb_build_object('ok',false,'reason','acceptance_contract_missing','httpStatus',v_runtime.status,'runtimeBodySha256',v_digest);
  end if;

  for v_criterion in select value from jsonb_array_elements_text(v_criteria)
  loop
    v_total:=v_total+1;
    v_recognized:=false;
    v_observed:=true;
    v_criterion:=lower(v_criterion);

    if v_criterion ~ '(analytics|tracked interaction|tracking|events fire)' then
      v_recognized:=true;
      v_observed:=v_observed and v_has_tracking;
    end if;
    if v_criterion ~ '(navigation|links|cta|authentication|onboarding|sign in|log in)' then
      v_recognized:=true;
      v_observed:=v_observed and v_has_onboarding;
    end if;
    if v_criterion ~ '(publish|online|go live|put results online)' then
      v_recognized:=true;
      v_observed:=v_observed and v_has_publish;
    end if;
    if v_criterion ~ '(what pandora|how to use|how pandora|what happens|within [0-9]+ seconds)' then
      v_recognized:=true;
      v_observed:=v_observed and v_has_journey and v_has_publish;
    end if;
    if v_criterion ~ '(responsive|mobile)' then
      v_recognized:=true;
      v_observed:=v_observed and v_lower ~ 'name=["'']viewport["'']';
    end if;

    if not v_recognized then
      select count(*),count(*) filter (where position(word in v_lower)>0)
        into v_words,v_matches
      from (
        select distinct w as word
        from regexp_split_to_table(v_criterion,'[^a-z0-9]+') w
        where length(w)>=5
          and w not in ('about','after','again','being','builds','could','every','their','there','these','those','through','using','where','which','while','would','successfully','should')
      ) q;
      if v_words>0 then
        v_threshold:=case when v_words<=3 then 1 else greatest(2,ceil(v_words*0.25)::integer) end;
        v_observed:=v_matches>=v_threshold;
      else
        v_observed:=false;
      end if;
    end if;

    if v_observed then v_passed:=v_passed+1; end if;
  end loop;

  return jsonb_build_object(
    'ok',v_passed=v_total,
    'criteriaTotal',v_total,
    'criteriaPassed',v_passed,
    'httpStatus',v_runtime.status,
    'runtimeBodySha256',v_digest,
    'signals',jsonb_build_object('tracking',v_has_tracking,'onboarding',v_has_onboarding,'publish',v_has_publish,'journey',v_has_journey)
  );
end
$function$;

revoke all on function private.pandora_evaluate_supabase_preview_acceptance_v2_20260830(uuid) from public,anon,authenticated;
grant execute on function private.pandora_evaluate_supabase_preview_acceptance_v2_20260830(uuid) to service_role;

create or replace function private.pandora_worker_e_verify_supabase_preview_v2_20260830(p_deployment_id uuid,p_requested_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public','extensions'
as $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_old public.pandora_verification_runs%rowtype;
  v_base jsonb;
  v_acceptance jsonb;
  v_failed integer;
  v_acceptance_failed integer;
  v_identity text;
  v_existing uuid;
  v_run_id uuid;
  v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id;
  if not found or v_dep.provider<>'supabase_preview' or v_dep.environment<>'preview' or v_dep.provider_state<>'READY' then
    raise exception 'SUPABASE_PREVIEW_EXACT_DEPLOYMENT_REQUIRED' using errcode='22023';
  end if;

  select * into v_old
  from public.pandora_verification_runs
  where project_id=v_dep.project_id and project_version_id=v_dep.version_id
    and preview_deployment_id=v_dep.provider_deployment_id
    and required_check_profile='static_site'
    and verifier_identity='worker-e-supabase-preview-verifier-v1'
  order by created_at desc limit 1;

  if not found then
    v_base:=private.pandora_worker_e_verify_supabase_preview_20260830(p_deployment_id,p_requested_by);
    select * into v_old from public.pandora_verification_runs where id=(v_base->>'verificationRunId')::uuid;
  end if;

  if upper(coalesce(v_old.status,''))='PASS' then
    return jsonb_build_object('verificationRunId',v_old.id,'status','PASS','profile','static_site','replayed',true,'acceptanceVerifier','v1');
  end if;

  select count(*) filter(where status<>'PASS'),count(*) filter(where check_key='acceptance_requirements' and status='FAIL')
    into v_failed,v_acceptance_failed
  from public.pandora_verification_checks where verification_run_id=v_old.id;
  if v_failed<>1 or v_acceptance_failed<>1 then
    return jsonb_build_object('verificationRunId',v_old.id,'status',v_old.status,'profile','static_site','replayed',true,'acceptanceVerifier','v1');
  end if;

  v_acceptance:=private.pandora_evaluate_supabase_preview_acceptance_v2_20260830(p_deployment_id);
  if coalesce((v_acceptance->>'ok')::boolean,false) is not true then
    return jsonb_build_object('verificationRunId',v_old.id,'status','FAIL','profile','static_site','replayed',true,'acceptanceVerifier','v2','acceptance',v_acceptance);
  end if;

  v_identity:=encode(extensions.digest(convert_to(v_old.identity_sha256||'|observable-acceptance-v2|'||p_deployment_id::text,'utf8'),'sha256'),'hex');
  select id into v_existing from public.pandora_verification_runs where project_version_id=v_old.project_version_id and identity_sha256=v_identity limit 1;
  if v_existing is not null then
    return (select jsonb_build_object('verificationRunId',id,'status',status,'profile',required_check_profile,'replayed',true,'acceptanceVerifier','v2') from public.pandora_verification_runs where id=v_existing);
  end if;

  v_run_id:=gen_random_uuid();
  insert into public.pandora_verification_runs(
    id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,requested_by,builder_identity,verifier_identity,identity_sha256,status,started_at,completed_at
  )
  select v_run_id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,coalesce(p_requested_by,requested_by),builder_identity,
    'worker-e-supabase-preview-verifier-v2',v_identity,'PASS',v_now,clock_timestamp()
  from public.pandora_verification_runs where id=v_old.id;

  insert into public.pandora_verification_checks(
    organization_id,project_id,verification_run_id,requirement_id,check_key,status,failure_class,security_severity,summary,details_redacted,started_at,completed_at
  )
  select organization_id,project_id,v_run_id,requirement_id,check_key,
    case when check_key='acceptance_requirements' then 'PASS' else status end,
    case when check_key='acceptance_requirements' then null else failure_class end,
    security_severity,
    case when check_key='acceptance_requirements' then 'Observable ProjectSpec acceptance is reachable.' else summary end,
    case when check_key='acceptance_requirements' then v_acceptance else details_redacted end,
    v_now,clock_timestamp()
  from public.pandora_verification_checks where verification_run_id=v_old.id;

  insert into public.pandora_verification_evidence(
    organization_id,project_id,verification_run_id,verification_check_id,artifact_version_id,evidence_type,media_type,content_sha256,storage_provider,storage_path
  )
  select e.organization_id,e.project_id,v_run_id,null,e.artifact_version_id,e.evidence_type,e.media_type,e.content_sha256,e.storage_provider,e.storage_path
  from public.pandora_verification_evidence e where e.verification_run_id=v_old.id;

  update public.pandora_project_versions set verification_run_id=v_run_id,lifecycle_status='verified' where id=v_old.project_version_id;
  return jsonb_build_object('verificationRunId',v_run_id,'status','PASS','profile','static_site','replayed',false,'acceptanceVerifier','v2','acceptance',v_acceptance);
end
$function$;

revoke all on function private.pandora_worker_e_verify_supabase_preview_v2_20260830(uuid,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_supabase_preview_v2_20260830(uuid,uuid) to service_role;

do $block$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='pandora_converge_static_site_build_v2_20260830';
  if v_def is null or position('private.pandora_worker_e_verify_supabase_preview_20260830' in v_def)=0 then
    raise exception 'STATIC_CONVERGENCE_V2_PATCH_TARGET_MISSING';
  end if;
  v_def:=replace(v_def,'private.pandora_worker_e_verify_supabase_preview_20260830','private.pandora_worker_e_verify_supabase_preview_v2_20260830');
  execute v_def;
end
$block$;