begin;

CREATE OR REPLACE FUNCTION private.pandora_static_preview_acceptance_v3(p_runtime_body text, p_project_name text, p_business_summary text, p_acceptance_scope jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_body text:=coalesce(p_runtime_body,'');
  v_body_lower text:=lower(coalesce(p_runtime_body,''));
  v_identity text;
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

  v_identity:=lower(trim(regexp_replace(
    coalesce(p_project_name,''),
    '[[:space:]]+(landing[[:space:]]+page|landing|website|web[[:space:]]*site|site|page|app|application|project)[[:space:]]*$',
    '',
    'i'
  )));
  if length(v_identity)<3 then
    v_identity:=lower(trim(coalesce(p_project_name,'')));
  end if;

  if length(v_identity)>=3 then
    if position(v_identity in v_body_lower)=0 then
      return false;
    end if;
  elsif nullif(trim(coalesce(p_business_summary,'')),'') is not null then
    if position(lower(left(trim(p_business_summary),80)) in v_body_lower)=0 then
      return false;
    end if;
  else
    return false;
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

CREATE OR REPLACE FUNCTION private.pandora_worker_e_verify_supabase_preview_20260830(p_deployment_id uuid, p_requested_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_art public.pandora_artifact_versions%rowtype;
  v_spec public.pandora_project_specs%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_op public.pandora_runtime_operations%rowtype;
  v_facts jsonb;
  v_token text;
  v_token_hash text;
  v_expires timestamptz;
  v_pat text;
  v_keys_response extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_object extensions.http_response;
  v_bundle jsonb;
  v_entry jsonb;
  v_plain text;
  v_index text:=null;
  v_artifact_ok boolean:=false;
  v_secret_ok boolean:=true;
  v_lint_ok boolean:=false;
  v_responsive_ok boolean:=false;
  v_provider_ok boolean:=false;
  v_runtime extensions.http_response;
  v_runtime_ok boolean:=false;
  v_runtime_body text:='';
  v_runtime_digest text;
  v_acceptance_ok boolean:=false;
  v_all boolean:=false;
  v_run_id uuid;
  v_identity text;
  v_now timestamptz:=clock_timestamp();
  v_builder text;
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id;
  if not found or v_dep.provider<>'supabase_preview' or v_dep.environment<>'preview'
     or v_dep.provider_project_id<>'pandora-preview-host' or v_dep.provider_state<>'READY'
     or v_dep.provider_deployment_id !~ '^spv_[0-9a-f]{32}$'
     or v_dep.url is null or v_dep.verification_state not in ('ready_for_verification','live_verified') then
    raise exception 'SUPABASE_PREVIEW_EXACT_DEPLOYMENT_REQUIRED' using errcode='22023';
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_dep.version_id;
  if not found or v_ver.project_id<>v_dep.project_id or v_ver.organization_id<>v_dep.organization_id
     or v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null
     or v_ver.project_spec_id is null or v_ver.build_job_id is null then
    raise exception 'SUPABASE_PREVIEW_VERSION_LINEAGE_INVALID' using errcode='22023';
  end if;
  select * into v_art from public.pandora_artifact_versions where id=v_ver.root_artifact_version_id;
  if not found or v_art.organization_id<>v_ver.organization_id or v_art.project_id<>v_ver.project_id
     or v_art.content_sha256<>v_ver.artifact_digest_sha256 or v_art.storage_provider<>'supabase_storage'
     or v_art.storage_bucket<>'pandora-build-artifacts' then
    raise exception 'SUPABASE_PREVIEW_ARTIFACT_INVALID' using errcode='22023';
  end if;
  select * into v_spec from public.pandora_project_specs where id=v_ver.project_spec_id;
  if not found then raise exception 'SUPABASE_PREVIEW_SPEC_INVALID' using errcode='22023'; end if;
  select * into v_job from public.pandora_build_jobs where id=v_ver.build_job_id;
  if not found then raise exception 'SUPABASE_PREVIEW_JOB_INVALID' using errcode='22023'; end if;
  v_builder:=coalesce(nullif(v_job.worker_identity,''),'worker-d-build-runtime');
  if v_builder='worker-e-runtime-verifier-v1' then raise exception 'builder and verifier must be independent' using errcode='22023'; end if;

  select * into v_op from public.pandora_runtime_operations
   where project_id=v_dep.project_id and project_version_id=v_dep.version_id and action='create_preview'
     and idempotency_key=v_dep.idempotency_key and status='succeeded' limit 1;
  if not found or v_op.provider_resource_id is distinct from v_dep.provider_deployment_id then
    raise exception 'SUPABASE_PREVIEW_OPERATION_INVALID' using errcode='22023';
  end if;
  v_facts:=coalesce(v_op.result_facts,'{}'::jsonb);
  if v_facts->>'previewProvider'<>'supabase_preview'
     or v_facts->>'providerDeploymentId'<>v_dep.provider_deployment_id
     or lower(coalesce(v_facts->>'artifactDigest',''))<>v_ver.artifact_digest_sha256 then
    raise exception 'SUPABASE_PREVIEW_FACTS_INVALID' using errcode='22023';
  end if;
  v_token:=split_part(regexp_replace(v_dep.url,'^https://mcpmaster[.]vercel[.]app/preview/','',''), '/', 1);
  if v_token !~ '^[0-9a-f]{64}$' then raise exception 'SUPABASE_PREVIEW_TOKEN_INVALID' using errcode='22023'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'utf8'),'sha256'),'hex');
  begin v_expires:=(v_facts->>'previewCapabilityExpiresAt')::timestamptz; exception when others then v_expires:=null; end;
  v_provider_ok:=v_token_hash=coalesce(v_facts->>'previewCapabilityHash','') and v_expires is not null and v_expires>v_now;

  for v_pat in
    select decrypted_secret from vault.decrypted_secrets
    where name in ('Supabase_access','mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'Supabase_access' then 0 when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_keys_response from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[extensions.http_header('authorization','Bearer '||v_pat),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Worker-E-Supabase-Preview/1.0')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_keys_response.status=200;
  end loop;
  if v_keys_response.status is distinct from 200 then v_pat:=null; raise exception 'SUPABASE_PREVIEW_STORAGE_AUTH_UNAVAILABLE' using errcode='55000'; end if;
  begin v_keys:=v_keys_response.content::jsonb; exception when others then v_pat:=null; raise exception 'SUPABASE_PREVIEW_STORAGE_KEYS_INVALID' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'SUPABASE_PREVIEW_STORAGE_KEY_UNAVAILABLE' using errcode='55000'; end if;
  select * into v_object from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/'||v_art.storage_bucket||'/'||v_art.storage_path)::varchar,
    array[extensions.http_header('authorization','Bearer '||v_service_role),extensions.http_header('apikey',v_service_role),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_object.status=200 and octet_length(coalesce(v_object.content,''))=v_art.byte_size
     and encode(extensions.digest(convert_to(coalesce(v_object.content,''),'utf8'),'sha256'),'hex')=v_art.content_sha256 then v_artifact_ok:=true; end if;
  if v_artifact_ok then begin v_bundle:=v_object.content::jsonb; exception when others then v_artifact_ok:=false; end; end if;
  if v_artifact_ok and (v_bundle->>'kind'<>'pandora.runtime-bundle.v1' or coalesce((v_bundle->>'schemaVersion')::integer,0)<>1
     or v_bundle->>'projectVersionId'<>v_ver.id::text or v_bundle->>'buildJobId'<>v_job.id::text) then v_artifact_ok:=false; end if;
  if v_artifact_ok then
    for v_entry in select value from jsonb_array_elements(coalesce(v_bundle->'files','[]'::jsonb)) loop
      begin v_plain:=convert_from(decode(v_entry->>'data','base64'),'utf8'); exception when others then v_artifact_ok:=false; exit; end;
      if encode(extensions.digest(convert_to(v_plain,'utf8'),'sha256'),'hex')<>v_entry->>'sha256' then v_artifact_ok:=false; exit; end if;
      if v_plain ~* '(AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|((api[_-]?key|secret|password|authorization)[[:space:]]*[:=][[:space:]]*[\"''][^\"'']{12,}[\"'']))' then v_secret_ok:=false; end if;
      if v_entry->>'file'='index.html' then v_index:=v_plain; end if;
    end loop;
  end if;
  v_lint_ok:=v_artifact_ok and v_index is not null and v_index ~* '<html' and v_index ~* '<body' and v_index ~* '</html>';
  v_responsive_ok:=v_lint_ok and v_index ~* 'name=[\"'']viewport[\"'']';

  if v_dep.url ~ '^https://[A-Za-z0-9.-]+(/.*)?$' then
    begin
      select * into v_runtime from extensions.http((
        'GET'::extensions.http_method,v_dep.url::varchar,
        array[extensions.http_header('user-agent','Pandora-Worker-E-Supabase-Preview/1.0'),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
        null::varchar,null::varchar
      )::extensions.http_request);
      v_runtime_ok:=v_runtime.status between 200 and 399
        and exists(select 1 from unnest(v_runtime.headers) h where lower((h).field)='content-type' and lower((h).value) like 'text/html%')
        and exists(select 1 from unnest(v_runtime.headers) h where lower((h).field)='content-security-policy'
          and strpos(lower((h).value),'sandbox')>0
          and strpos(lower((h).value),'allow-scripts')>0
          and strpos(lower((h).value),'allow-same-origin')=0);
      v_runtime_body:=left(coalesce(v_runtime.content,''),1048576);
    exception when others then v_runtime_ok:=false; end;
  end if;
  v_runtime_digest:=encode(extensions.digest(convert_to(coalesce(v_runtime_body,''),'utf8'),'sha256'),'hex');
  v_acceptance_ok:=v_runtime_ok and private.pandora_static_preview_acceptance_v3(
    v_runtime_body,
    (select name from public.projectos_projects where id=v_ver.project_id),
    v_spec.business_summary,
    v_spec.acceptance_scope
  );

  v_identity:=encode(extensions.digest(convert_to(concat_ws('|',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,'static_site_acceptance_v3',v_dep.url,v_ver.source_sha256,v_ver.artifact_digest_sha256,coalesce(v_ver.migration_set_digest_sha256,''),coalesce(v_ver.runtime_target_digest_sha256,'')),'utf8'),'sha256'),'hex');
  select id into v_run_id from public.pandora_verification_runs where project_version_id=v_ver.id and identity_sha256=v_identity limit 1;
  if v_run_id is not null then
    return (select jsonb_build_object('verificationRunId',id,'status',status,'profile',required_check_profile,'replayed',true) from public.pandora_verification_runs where id=v_run_id);
  end if;
  v_run_id:=gen_random_uuid();
  insert into public.pandora_verification_runs(
    id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,requested_by,builder_identity,verifier_identity,identity_sha256,status,started_at
  ) values (
    v_run_id,v_ver.organization_id,v_ver.project_id,v_ver.project_spec_id,v_ver.id,v_ver.build_job_id,v_ver.source_kind,v_ver.source_ref,v_ver.source_commit,v_ver.source_sha256,v_ver.artifact_digest_sha256,
    v_ver.migration_set_digest_sha256,v_ver.runtime_target_digest_sha256,v_dep.provider_deployment_id,'preview','static_site',p_requested_by,v_builder,'worker-e-supabase-preview-verifier-v1',v_identity,'RUNNING',v_now
  );
  insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,failure_class,summary,details_redacted,started_at,completed_at)
  values
    (v_ver.organization_id,v_ver.project_id,v_run_id,'source_format',case when v_artifact_ok then 'PASS' else 'FAIL' end,case when v_artifact_ok then null else 'source' end,case when v_artifact_ok then 'Exact runtime bundle is canonical.' else 'Exact runtime bundle failed canonical validation.' end,jsonb_build_object('artifactDigest',v_ver.artifact_digest_sha256),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'source_lint',case when v_lint_ok then 'PASS' else 'FAIL' end,case when v_lint_ok then null else 'source' end,case when v_lint_ok then 'Static entrypoint structure is valid.' else 'Static entrypoint structure failed.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'secret_scan',case when v_secret_ok then 'PASS' else 'FAIL' end,case when v_secret_ok then null else 'security' end,case when v_secret_ok then 'No standing secret material detected.' else 'Secret-shaped material detected.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'visual_responsive',case when v_responsive_ok then 'PASS' else 'FAIL' end,case when v_responsive_ok then null else 'visual' end,case when v_responsive_ok then 'Responsive viewport contract present.' else 'Responsive viewport contract missing.' end,'{}'::jsonb,v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'runtime_health',case when v_runtime_ok and v_provider_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_provider_ok then null else 'runtime' end,case when v_runtime_ok and v_provider_ok then 'Exact Supabase preview capability is live and answers HTTPS.' else 'Supabase preview runtime health failed.' end,jsonb_build_object('httpStatus',v_runtime.status,'runtimeBodySha256',v_runtime_digest,'previewProvider','supabase_preview'),v_now,clock_timestamp()),
    (v_ver.organization_id,v_ver.project_id,v_run_id,'acceptance_requirements',case when v_acceptance_ok then 'PASS' else 'FAIL' end,case when v_acceptance_ok then null else 'acceptance' end,case when v_acceptance_ok then 'Observable ProjectSpec acceptance is reachable.' else 'Observable ProjectSpec acceptance failed.' end,'{}'::jsonb,v_now,clock_timestamp());
  select bool_and(status='PASS') into v_all from public.pandora_verification_checks where verification_run_id=v_run_id;
  update public.pandora_verification_runs set status=case when v_all then 'PASS' else 'FAIL' end,completed_at=clock_timestamp() where id=v_run_id;
  insert into public.pandora_verification_evidence(organization_id,project_id,verification_run_id,artifact_version_id,evidence_type,media_type,content_sha256,storage_provider,storage_path)
  values(v_ver.organization_id,v_ver.project_id,v_run_id,v_art.id,'artifact_identity','application/json',v_art.content_sha256,v_art.storage_provider,v_art.storage_path);
  if v_all then update public.pandora_project_versions set verification_run_id=v_run_id,lifecycle_status='verified' where id=v_ver.id; end if;
  return jsonb_build_object('verificationRunId',v_run_id,'status',case when v_all then 'PASS' else 'FAIL' end,'profile','static_site','replayed',false,'providerReady',v_provider_ok,'runtimeHealthy',v_runtime_ok,'previewProvider','supabase_preview');
end;
$function$;

comment on function private.pandora_static_preview_acceptance_v3(text,text,text,jsonb) is
'Observable static-page acceptance: requires a functional acceptance scope, meaningful project identity, resolvable internal fragment links, and defined inline click handlers.';

comment on function private.pandora_worker_e_verify_supabase_preview_20260830(uuid,uuid) is
'Worker E preview verification requires renderable HTML plus observable static-page acceptance. Verification identity v3 prevents replay of legacy substring-only acceptance results.';

commit;
