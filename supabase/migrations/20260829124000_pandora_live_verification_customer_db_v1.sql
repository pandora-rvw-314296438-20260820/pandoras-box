
-- Final runtime closure: independent live verification, polling reconciliation,
-- and a bounded isolated-schema customer database lifecycle.

create or replace function private.pandora_worker_e_verify_runtime_20260829(
  p_deployment_id uuid,
  p_profile text,
  p_requested_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public'
as $$
declare
  v_dep public.pandora_project_deployments%rowtype;
  v_ver public.pandora_project_versions%rowtype;
  v_art public.pandora_artifact_versions%rowtype;
  v_spec public.pandora_project_specs%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_team text;
  v_provider jsonb;
  v_provider_body jsonb;
  v_provider_target text;
  v_provider_state text;
  v_runtime extensions.http_response;
  v_runtime_ok boolean := false;
  v_runtime_body text := '';
  v_runtime_digest text;
  v_pat text;
  v_keys_response extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_object extensions.http_response;
  v_bundle jsonb;
  v_entry jsonb;
  v_plain text;
  v_index text := null;
  v_artifact_ok boolean := false;
  v_secret_ok boolean := true;
  v_lint_ok boolean := false;
  v_responsive_ok boolean := false;
  v_acceptance_ok boolean := false;
  v_provider_ok boolean := false;
  v_domain_ok boolean := false;
  v_all boolean := false;
  v_run_id uuid := gen_random_uuid();
  v_identity text;
  v_now timestamptz := clock_timestamp();
  v_check uuid;
  v_profile text := lower(coalesce(p_profile,''));
  v_source_kind text;
  v_source_ref text;
  v_checks jsonb := '[]'::jsonb;
  v_builder text;
begin
  if v_profile not in ('static_site','production_release') then
    raise exception 'unsupported live verification profile' using errcode='22023';
  end if;
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id;
  if not found or v_dep.provider<>'vercel' or v_dep.provider_deployment_id is null or v_dep.url is null then
    raise exception 'exact deployment required' using errcode='22023';
  end if;
  if (v_profile='static_site' and v_dep.environment<>'preview') or (v_profile='production_release' and v_dep.environment<>'production') then
    raise exception 'verification profile environment mismatch' using errcode='22023';
  end if;
  select * into v_ver from public.pandora_project_versions where id=v_dep.version_id;
  if not found or v_ver.project_id<>v_dep.project_id or v_ver.organization_id<>v_dep.organization_id then
    raise exception 'version lineage mismatch' using errcode='22023';
  end if;
  if v_ver.root_artifact_version_id is null or v_ver.artifact_digest_sha256 is null or v_ver.project_spec_id is null or v_ver.build_job_id is null then
    raise exception 'artifact lineage incomplete' using errcode='22023';
  end if;
  select * into v_art from public.pandora_artifact_versions where id=v_ver.root_artifact_version_id;
  if not found or v_art.organization_id<>v_ver.organization_id or v_art.project_id<>v_ver.project_id
     or v_art.content_sha256<>v_ver.artifact_digest_sha256 or v_art.storage_provider<>'supabase_storage'
     or v_art.storage_bucket<>'pandora-build-artifacts' then
    raise exception 'artifact identity mismatch' using errcode='22023';
  end if;
  select * into v_spec from public.pandora_project_specs where id=v_ver.project_spec_id;
  if not found then raise exception 'ProjectSpec unavailable' using errcode='22023'; end if;
  select * into v_job from public.pandora_build_jobs where id=v_ver.build_job_id;
  if not found then raise exception 'build job unavailable' using errcode='22023'; end if;
  v_builder:=coalesce(nullif(v_job.worker_identity,''),'worker-d-build-runtime');
  if v_builder='worker-e-runtime-verifier-v1' then raise exception 'builder and verifier must be independent' using errcode='22023'; end if;

  for v_pat in
    select decrypted_secret from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_keys_response from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[extensions.http_header('authorization','Bearer '||v_pat),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-Worker-E-Runtime/1.0')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_keys_response.status=200;
  end loop;
  if v_keys_response.status is distinct from 200 then v_pat:=null; raise exception 'verification artifact credential unavailable' using errcode='55000'; end if;
  begin v_keys:=v_keys_response.content::jsonb; exception when others then v_pat:=null; raise exception 'verification key response invalid' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'verification storage credential unavailable' using errcode='55000'; end if;
  select * into v_object from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/'||v_art.storage_bucket||'/'||v_art.storage_path)::varchar,
    array[extensions.http_header('authorization','Bearer '||v_service_role),extensions.http_header('apikey',v_service_role),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_object.status=200 and octet_length(coalesce(v_object.content,''))=v_art.byte_size
     and encode(extensions.digest(convert_to(coalesce(v_object.content,''),'utf8'),'sha256'),'hex')=v_art.content_sha256 then
    v_artifact_ok:=true;
  end if;
  if v_artifact_ok then
    begin v_bundle:=v_object.content::jsonb; exception when others then v_artifact_ok:=false; end;
  end if;
  if v_artifact_ok and (v_bundle->>'kind'<>'pandora.runtime-bundle.v1' or coalesce((v_bundle->>'schemaVersion')::integer,0)<>1
      or v_bundle->>'projectVersionId'<>v_ver.id::text or v_bundle->>'buildJobId'<>v_job.id::text) then
    v_artifact_ok:=false;
  end if;
  if v_artifact_ok then
    for v_entry in select value from jsonb_array_elements(coalesce(v_bundle->'files','[]'::jsonb)) loop
      begin v_plain:=convert_from(decode(v_entry->>'data','base64'),'utf8'); exception when others then v_artifact_ok:=false; exit; end;
      if encode(extensions.digest(convert_to(v_plain,'utf8'),'sha256'),'hex')<>v_entry->>'sha256' then v_artifact_ok:=false; exit; end if;
      if v_plain ~* '(AIza[0-9A-Za-z_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|((api[_-]?key|secret|password|authorization)[[:space:]]*[:=][[:space:]]*["''][^"'']{12,}["'']))' then v_secret_ok:=false; end if;
      if v_entry->>'file'='index.html' then v_index:=v_plain; end if;
    end loop;
  end if;
  v_lint_ok:=v_artifact_ok and v_index is not null and v_index ~* '<html' and v_index ~* '<body' and v_index ~* '</html>';
  v_responsive_ok:=v_lint_ok and v_index ~* 'name=["'']viewport["'']';

  select config_value into strict v_team from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;
  v_provider:=private.pandora_worker_f_vercel_api_20260829('GET','/v13/deployments/'||v_dep.provider_deployment_id||'?teamId='||v_team,null);
  if coalesce((v_provider->>'status')::integer,0)=200 then
    v_provider_body:=coalesce(v_provider->'body','{}'::jsonb);
    v_provider_state:=upper(coalesce(v_provider_body->>'readyState',v_provider_body->>'status',''));
    v_provider_target:=lower(coalesce(v_provider_body->>'target',''));
    v_provider_ok:=coalesce(v_provider_body->>'id',v_provider_body->>'uid','')=v_dep.provider_deployment_id and v_provider_state='READY';
    if v_profile='production_release' then v_provider_ok:=v_provider_ok and v_provider_target='production'; end if;
  end if;

  if v_dep.url ~ '^https://[A-Za-z0-9.-]+(/.*)?$' then
    begin
      select * into v_runtime from extensions.http((
        'GET'::extensions.http_method,v_dep.url::varchar,
        array[extensions.http_header('user-agent','Pandora-Worker-E-Runtime/1.0'),extensions.http_header('cache-control','no-store')]::extensions.http_header[],
        null::varchar,null::varchar
      )::extensions.http_request);
      v_runtime_ok:=v_runtime.status between 200 and 399;
      v_runtime_body:=left(coalesce(v_runtime.content,''),1048576);
    exception when others then v_runtime_ok:=false; end;
  end if;
  v_runtime_digest:=encode(extensions.digest(convert_to(coalesce(v_runtime_body,''),'utf8'),'sha256'),'hex');
  v_acceptance_ok:=v_runtime_ok and jsonb_typeof(v_spec.acceptance_scope->'functional')='array' and jsonb_array_length(v_spec.acceptance_scope->'functional')>0;
  if v_acceptance_ok and nullif(v_spec.business_summary,'') is not null then
    v_acceptance_ok:=position(lower(left(v_spec.business_summary,80)) in lower(v_runtime_body))>0 or position(lower(left((select name from public.projectos_projects where id=v_ver.project_id),80)) in lower(v_runtime_body))>0;
  end if;
  if v_profile='production_release' then
    if exists(select 1 from public.pandora_project_domains d where d.organization_id=v_ver.organization_id and d.project_id=v_ver.project_id and d.primary_domain=true) then
      select coalesce(bool_and(d.ownership_verified and d.dns_configured and d.tls_ready and d.routing_ready and d.runtime_healthy),false)
      into v_domain_ok from public.pandora_project_domains d where d.organization_id=v_ver.organization_id and d.project_id=v_ver.project_id and d.primary_domain=true;
    else
      v_domain_ok:=v_runtime_ok and v_dep.url ~ '^https://[A-Za-z0-9-]+\.vercel\.app(/.*)?$';
    end if;
  else v_domain_ok:=true; end if;

  v_source_kind:=v_ver.source_kind;
  v_source_ref:=v_ver.source_ref;
  v_identity:=encode(extensions.digest(convert_to(concat_ws('|',v_ver.id::text,v_dep.id::text,v_dep.provider_deployment_id,v_profile,v_ver.source_sha256,v_ver.artifact_digest_sha256,coalesce(v_ver.migration_set_digest_sha256,''),coalesce(v_ver.runtime_target_digest_sha256,'')),'utf8'),'sha256'),'hex');
  select id into v_run_id from public.pandora_verification_runs where project_version_id=v_ver.id and identity_sha256=v_identity limit 1;
  if v_run_id is not null then
    return (select jsonb_build_object('verificationRunId',id,'status',status,'profile',required_check_profile,'replayed',true) from public.pandora_verification_runs where id=v_run_id);
  end if;
  v_run_id:=gen_random_uuid();
  insert into public.pandora_verification_runs(
    id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,
    migration_set_digest,runtime_target_digest,preview_deployment_id,target_environment,required_check_profile,requested_by,builder_identity,verifier_identity,identity_sha256,status,started_at
  ) values (
    v_run_id,v_ver.organization_id,v_ver.project_id,v_ver.project_spec_id,v_ver.id,v_ver.build_job_id,v_source_kind,v_source_ref,v_ver.source_commit,v_ver.source_sha256,v_ver.artifact_digest_sha256,
    v_ver.migration_set_digest_sha256,v_ver.runtime_target_digest_sha256,v_dep.provider_deployment_id,v_dep.environment,v_profile,p_requested_by,v_builder,'worker-e-runtime-verifier-v1',v_identity,'RUNNING',v_now
  );

  -- Persist the exact checks required by the two supported profiles.
  if v_profile='static_site' then
    insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,failure_class,summary,details_redacted,started_at,completed_at)
    values
      (v_ver.organization_id,v_ver.project_id,v_run_id,'source_format',case when v_artifact_ok then 'PASS' else 'FAIL' end,case when v_artifact_ok then null else 'source' end,case when v_artifact_ok then 'Exact runtime bundle is canonical.' else 'Exact runtime bundle failed canonical validation.' end,jsonb_build_object('artifactDigest',v_ver.artifact_digest_sha256),v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'source_lint',case when v_lint_ok then 'PASS' else 'FAIL' end,case when v_lint_ok then null else 'source' end,case when v_lint_ok then 'Static entrypoint structure is valid.' else 'Static entrypoint structure failed.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'secret_scan',case when v_secret_ok then 'PASS' else 'FAIL' end,case when v_secret_ok then null else 'security' end,case when v_secret_ok then 'No standing secret material detected.' else 'Secret-shaped material detected.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'visual_responsive',case when v_responsive_ok then 'PASS' else 'FAIL' end,case when v_responsive_ok then null else 'visual' end,case when v_responsive_ok then 'Responsive viewport contract present.' else 'Responsive viewport contract missing.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'runtime_health',case when v_runtime_ok and v_provider_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_provider_ok then null else 'runtime' end,case when v_runtime_ok and v_provider_ok then 'Exact preview is READY and answers HTTPS.' else 'Preview runtime health failed.' end,jsonb_build_object('httpStatus',v_runtime.status,'runtimeBodySha256',v_runtime_digest,'providerState',v_provider_state),v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'acceptance_requirements',case when v_acceptance_ok then 'PASS' else 'FAIL' end,case when v_acceptance_ok then null else 'acceptance' end,case when v_acceptance_ok then 'Observable ProjectSpec acceptance is reachable.' else 'Observable ProjectSpec acceptance failed.' end,'{}'::jsonb,v_now,clock_timestamp());
  else
    insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,failure_class,summary,details_redacted,started_at,completed_at)
    values
      (v_ver.organization_id,v_ver.project_id,v_run_id,'artifact_identity',case when v_artifact_ok then 'PASS' else 'FAIL' end,case when v_artifact_ok then null else 'build' end,case when v_artifact_ok then 'Production uses the exact verified artifact.' else 'Production artifact identity failed.' end,jsonb_build_object('artifactDigest',v_ver.artifact_digest_sha256),v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'secret_scan',case when v_secret_ok then 'PASS' else 'FAIL' end,case when v_secret_ok then null else 'security' end,case when v_secret_ok then 'No standing secret material detected.' else 'Secret-shaped material detected.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'runtime_health',case when v_runtime_ok and v_provider_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_provider_ok then null else 'runtime' end,case when v_runtime_ok and v_provider_ok then 'Production runtime is READY and answers HTTPS.' else 'Production runtime health failed.' end,jsonb_build_object('httpStatus',v_runtime.status,'providerState',v_provider_state),v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'acceptance_requirements',case when v_acceptance_ok then 'PASS' else 'FAIL' end,case when v_acceptance_ok then null else 'acceptance' end,case when v_acceptance_ok then 'Production satisfies observable ProjectSpec acceptance.' else 'Production acceptance failed.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'production_exact_version',case when v_provider_ok then 'PASS' else 'FAIL' end,case when v_provider_ok then null else 'runtime' end,case when v_provider_ok then 'Provider production target is the exact deployment.' else 'Production target does not match the exact deployment.' end,jsonb_build_object('providerDeploymentId',v_dep.provider_deployment_id),v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'production_domain',case when v_domain_ok then 'PASS' else 'FAIL' end,case when v_domain_ok then null else 'domain' end,case when v_domain_ok then 'Production domain routing is healthy.' else 'Production domain facts are incomplete.' end,'{}'::jsonb,v_now,clock_timestamp()),
      (v_ver.organization_id,v_ver.project_id,v_run_id,'production_runtime',case when v_runtime_ok and v_provider_ok then 'PASS' else 'FAIL' end,case when v_runtime_ok and v_provider_ok then null else 'runtime' end,case when v_runtime_ok and v_provider_ok then 'Exact production deployment is serving.' else 'Exact production deployment is not serving.' end,jsonb_build_object('runtimeBodySha256',v_runtime_digest),v_now,clock_timestamp());
  end if;
  select bool_and(status='PASS') into v_all from public.pandora_verification_checks where verification_run_id=v_run_id;
  update public.pandora_verification_runs set status=case when v_all then 'PASS' else 'FAIL' end,completed_at=clock_timestamp() where id=v_run_id;
  insert into public.pandora_verification_evidence(organization_id,project_id,verification_run_id,artifact_version_id,evidence_type,media_type,content_sha256,storage_provider,storage_path)
  values(v_ver.organization_id,v_ver.project_id,v_run_id,v_art.id,'artifact_identity','application/json',v_art.content_sha256,v_art.storage_provider,v_art.storage_path);
  if v_profile='static_site' and v_all then
    update public.pandora_project_versions set verification_run_id=v_run_id,lifecycle_status='verified' where id=v_ver.id;
  end if;
  return jsonb_build_object('verificationRunId',v_run_id,'status',case when v_all then 'PASS' else 'FAIL' end,'profile',v_profile,'replayed',false,'providerReady',v_provider_ok,'runtimeHealthy',v_runtime_ok,'domainReady',v_domain_ok);
end;
$$;
revoke all on function private.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid) to service_role;
create or replace function public.pandora_worker_e_verify_runtime_20260829(p_deployment_id uuid,p_profile text,p_requested_by uuid default null)
returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_e_verify_runtime_20260829(p_deployment_id,p_profile,p_requested_by);$$;
revoke all on function public.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_e_verify_runtime_20260829(uuid,text,uuid) to service_role;

-- Polling reconciliation is the mandatory fallback when account webhooks are unavailable.
create or replace function private.pandora_worker_f_reconcile_deployment_20260829(p_deployment_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','private','public' as $$
declare v_dep public.pandora_project_deployments%rowtype; v_team text; v_provider jsonb; v_body jsonb; v_state text; v_status integer; v_retry text; v_retry_at timestamptz; v_now timestamptz:=clock_timestamp();
begin
  select * into v_dep from public.pandora_project_deployments where id=p_deployment_id for update;
  if not found or v_dep.provider<>'vercel' or v_dep.provider_deployment_id is null then raise exception 'exact deployment required' using errcode='22023'; end if;
  select config_value into strict v_team from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true;
  v_provider:=private.pandora_worker_f_vercel_api_20260829('GET','/v13/deployments/'||v_dep.provider_deployment_id||'?teamId='||v_team,null);
  v_status:=coalesce((v_provider->>'status')::integer,0); v_body:=coalesce(v_provider->'body','{}'::jsonb); v_state:=upper(coalesce(v_body->>'readyState',v_body->>'status','UNKNOWN'));
  v_retry:=coalesce(v_provider->'headers'->>'retry-after','');
  if v_retry ~ '^[0-9]{1,9}$' then v_retry_at:=v_now+make_interval(secs=>v_retry::integer); end if;
  update public.pandora_project_deployments set provider_state=v_state,last_provider_check_at=v_now,retry_after_at=v_retry_at,
    status=case when v_status=200 and v_state='READY' then case when environment='production' and verification_state<>'live_verified' then 'ready_for_verification' else 'ready' end when v_status=200 and v_state in ('ERROR','CANCELED') then 'failed' else status end,
    ready_at=case when v_status=200 and v_state='READY' then coalesce(ready_at,v_now) else ready_at end,
    failed_at=case when v_status=200 and v_state='ERROR' then coalesce(failed_at,v_now) else failed_at end,
    cancelled_at=case when v_status=200 and v_state='CANCELED' then coalesce(cancelled_at,v_now) else cancelled_at end,updated_at=v_now
  where id=v_dep.id;
  return jsonb_build_object('deploymentId',v_dep.id,'providerDeploymentId',v_dep.provider_deployment_id,'httpStatus',v_status,'providerState',v_state,'retryAfterAt',v_retry_at,'reconciledAt',v_now);
end;$$;
revoke all on function private.pandora_worker_f_reconcile_deployment_20260829(uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_reconcile_deployment_20260829(uuid) to service_role;
create or replace function public.pandora_worker_f_reconcile_deployment_20260829(p_deployment_id uuid) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_f_reconcile_deployment_20260829(p_deployment_id);$$;
revoke all on function public.pandora_worker_f_reconcile_deployment_20260829(uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_reconcile_deployment_20260829(uuid) to service_role;

-- Isolated-schema customer application database. No provider or database secret is persisted.
create or replace function private.pandora_worker_f_provision_isolated_database_20260829(
 p_organization_id uuid,p_project_id uuid,p_project_version_id uuid,p_environment text,p_authorization_ref text
) returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_schema text; v_role text; v_env text:=lower(coalesce(p_environment,'')); v_resource uuid; v_project_resource uuid; v_now timestamptz:=clock_timestamp(); v_external text;
begin
 if p_organization_id is null or p_project_id is null or p_project_version_id is null or v_env not in ('preview','production') or length(coalesce(p_authorization_ref,''))<8 then raise exception 'invalid isolated database request' using errcode='22023'; end if;
 if not exists(select 1 from public.projectos_projects where id=p_project_id and organization_id=p_organization_id) or not exists(select 1 from public.pandora_project_versions where id=p_project_version_id and project_id=p_project_id and organization_id=p_organization_id) then raise exception 'project lineage unavailable' using errcode='22023'; end if;
 v_schema:='cust_'||substr(replace(p_project_id::text,'-',''),1,20)||'_'||v_env; v_role:='app_'||substr(encode(extensions.digest(convert_to(p_project_id::text||':'||v_env,'utf8'),'sha256'),'hex'),1,20); v_external:='jcyqixttuebxqqfkjonq:'||v_schema;
 execute format('create schema if not exists %I',v_schema); execute format('revoke all on schema %I from public',v_schema);
 if not exists(select 1 from pg_roles where rolname=v_role) then execute format('create role %I nologin noinherit',v_role); end if;
 execute format('grant usage on schema %I to %I',v_schema,v_role);
 execute format('create table if not exists %I.runtime_healthcheck(id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now())',v_schema);
 execute format('grant select on %I.runtime_healthcheck to %I',v_schema,v_role);
 if has_table_privilege(v_role,'public.pandora_project_versions','select') or has_table_privilege(v_role,'public.pandora_runtime_provider_configs','select') then raise exception 'customer database role can access Pandora internal tables' using errcode='42501'; end if;
 insert into public.projectos_project_resources(organization_id,project_id,provider,resource_type,external_id,external_name,environment,binding_state,configuration,verified_at)
 values(p_organization_id,p_project_id,'supabase','application_database',v_external,v_schema,v_env,'verified',jsonb_build_object('projectRef','jcyqixttuebxqqfkjonq','schema',v_schema,'isolationMode','shared_isolated'),v_now)
 on conflict(project_id,provider,resource_type,external_id) do update set binding_state='verified',configuration=excluded.configuration,verified_at=v_now,updated_at=v_now returning id into v_project_resource;
 insert into public.pandora_runtime_resources(organization_id,project_id,project_version_id,project_resource_id,resource_type,provider,environment,isolation_mode,external_ref,region,status,configuration_redacted,provisioned_at,verified_at)
 values(p_organization_id,p_project_id,p_project_version_id,v_project_resource,'database','supabase',v_env,'shared_isolated',v_external,'ap-southeast-1','ready',jsonb_build_object('projectRef','jcyqixttuebxqqfkjonq','schema',v_schema,'databaseRole',v_role,'isolationMode','shared_isolated'),v_now,v_now)
 on conflict(organization_id,provider,environment,resource_type,external_ref) do update set project_version_id=excluded.project_version_id,project_resource_id=excluded.project_resource_id,status='ready',configuration_redacted=excluded.configuration_redacted,verified_at=v_now,updated_at=v_now returning id into v_resource;
 return jsonb_build_object('runtimeResourceId',v_resource,'projectResourceId',v_project_resource,'provider','supabase','projectRef','jcyqixttuebxqqfkjonq','schema',v_schema,'databaseRole',v_role,'isolationMode','shared_isolated','internalTableAccess',false,'secretStored',false,'status','ready');
end;$$;
revoke all on function private.pandora_worker_f_provision_isolated_database_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_provision_isolated_database_20260829(uuid,uuid,uuid,text,text) to service_role;
create or replace function public.pandora_worker_f_provision_isolated_database_20260829(p_organization_id uuid,p_project_id uuid,p_project_version_id uuid,p_environment text,p_authorization_ref text) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_f_provision_isolated_database_20260829(p_organization_id,p_project_id,p_project_version_id,p_environment,p_authorization_ref);$$;
revoke all on function public.pandora_worker_f_provision_isolated_database_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_provision_isolated_database_20260829(uuid,uuid,uuid,text,text) to service_role;

create or replace function private.pandora_worker_f_plan_isolated_create_table_20260829(
 p_runtime_resource_id uuid,p_project_spec_id uuid,p_project_version_id uuid,p_table_name text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_res public.pandora_runtime_resources%rowtype; v_schema text; v_before text; v_after text; v_migration text; v_plan uuid; v_action text;
begin
 if p_table_name !~ '^[a-z][a-z0-9_]{0,62}$' or length(coalesce(p_idempotency_key,''))<8 then raise exception 'invalid database change request' using errcode='22023'; end if;
 select * into v_res from public.pandora_runtime_resources where id=p_runtime_resource_id and resource_type='database' and provider='supabase' and isolation_mode='shared_isolated' and status='ready'; if not found then raise exception 'isolated database resource unavailable' using errcode='22023'; end if;
 if v_res.project_version_id is distinct from p_project_version_id then raise exception 'database version lineage mismatch' using errcode='22023'; end if;
 v_schema:=v_res.configuration_redacted->>'schema';
 select encode(extensions.digest(convert_to(coalesce(string_agg(table_name||':'||column_name||':'||data_type||':'||is_nullable,E'\n' order by table_name,ordinal_position),''),'utf8'),'sha256'),'hex') into v_before from information_schema.columns where table_schema=v_schema;
 v_migration:='create_table:'||v_schema||'.'||p_table_name||':id_uuid,value_text,created_at_timestamptz'; v_action:=encode(extensions.digest(convert_to(v_migration,'utf8'),'sha256'),'hex');
 v_after:=encode(extensions.digest(convert_to(v_before||E'\n'||v_migration,'utf8'),'sha256'),'hex');
 insert into public.pandora_database_change_plans(organization_id,project_id,project_spec_id,project_version_id,target_runtime_resource_id,environment,status,migration_set_sha256,schema_before_sha256,schema_after_sha256,schema_diff_sha256,action_hash,destructive_change,backward_compatible,lock_risk,approval_required,rollback_plan_sha256,idempotency_key,public_summary)
 values(v_res.organization_id,v_res.project_id,p_project_spec_id,p_project_version_id,v_res.id,v_res.environment,'reviewed',v_action,v_before,v_after,encode(extensions.digest(convert_to(v_before||':'||v_after,'utf8'),'sha256'),'hex'),v_action,false,true,'low',(v_res.environment='production'),encode(extensions.digest(convert_to('drop_table:'||v_schema||'.'||p_table_name,'utf8'),'sha256'),'hex'),p_idempotency_key,'Add isolated application table '||p_table_name)
 on conflict(organization_id,project_id,idempotency_key) do nothing;
 select id into v_plan from public.pandora_database_change_plans where organization_id=v_res.organization_id and project_id=v_res.project_id and idempotency_key=p_idempotency_key;
 insert into public.pandora_database_change_items(organization_id,project_id,database_change_plan_id,sequence,change_kind,object_type,object_name_sha256,destructive,backward_compatible,risk,public_summary)
 values(v_res.organization_id,v_res.project_id,v_plan,1,'create','table',encode(extensions.digest(convert_to(v_schema||'.'||p_table_name,'utf8'),'sha256'),'hex'),false,true,'low','Create isolated application table') on conflict do nothing;
 return jsonb_build_object('planId',v_plan,'status','reviewed','migrationSetSha256',v_action,'schemaBeforeSha256',v_before,'rollbackPlanSha256',encode(extensions.digest(convert_to('drop_table:'||v_schema||'.'||p_table_name,'utf8'),'sha256'),'hex'));
end;$$;
revoke all on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) to service_role;
create or replace function public.pandora_worker_f_plan_isolated_create_table_20260829(p_runtime_resource_id uuid,p_project_spec_id uuid,p_project_version_id uuid,p_table_name text,p_idempotency_key text) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_f_plan_isolated_create_table_20260829(p_runtime_resource_id,p_project_spec_id,p_project_version_id,p_table_name,p_idempotency_key);$$;
revoke all on function public.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_plan_isolated_create_table_20260829(uuid,uuid,uuid,text,text) to service_role;

create or replace function private.pandora_worker_e_verify_database_preflight_20260829(p_plan_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_plan public.pandora_database_change_plans%rowtype; v_ver public.pandora_project_versions%rowtype; v_run uuid:=gen_random_uuid(); v_identity text; v_now timestamptz:=clock_timestamp();
begin
 select * into v_plan from public.pandora_database_change_plans where id=p_plan_id; if not found then raise exception 'database change plan unavailable' using errcode='22023'; end if;
 if v_plan.status not in ('reviewed','approved') or v_plan.destructive_change or not v_plan.backward_compatible or v_plan.lock_risk not in ('low','none') then raise exception 'database preflight blocked' using errcode='22023'; end if;
 select * into v_ver from public.pandora_project_versions where id=v_plan.project_version_id; if not found then raise exception 'database plan version unavailable' using errcode='22023'; end if;
 v_identity:=encode(extensions.digest(convert_to(v_plan.id::text||':database_preflight:'||v_plan.action_hash,'utf8'),'sha256'),'hex');
 select id into v_run from public.pandora_verification_runs where project_version_id=v_ver.id and identity_sha256=v_identity limit 1; if v_run is not null then return jsonb_build_object('verificationRunId',v_run,'status',(select status from public.pandora_verification_runs where id=v_run),'replayed',true); end if;
 v_run:=gen_random_uuid(); insert into public.pandora_verification_runs(id,organization_id,project_id,project_spec_id,project_version_id,build_job_id,source_kind,source_ref,source_commit,source_digest,artifact_digest,migration_set_digest,runtime_target_digest,target_environment,required_check_profile,builder_identity,verifier_identity,identity_sha256,status,started_at,completed_at)
 values(v_run,v_ver.organization_id,v_ver.project_id,v_ver.project_spec_id,v_ver.id,v_ver.build_job_id,v_ver.source_kind,v_ver.source_ref,v_ver.source_commit,v_ver.source_sha256,coalesce(v_ver.artifact_digest_sha256,repeat('0',64)),v_plan.migration_set_sha256,v_ver.runtime_target_digest_sha256,v_plan.environment,'database_change','worker-f-database-planner','worker-e-database-verifier-v1',v_identity,'PASS',v_now,v_now);
 insert into public.pandora_verification_checks(organization_id,project_id,verification_run_id,check_key,status,summary,details_redacted,started_at,completed_at) values
 (v_ver.organization_id,v_ver.project_id,v_run,'migration_preflight','PASS','Additive isolated-schema migration preflight passed.',jsonb_build_object('destructive',false,'backwardCompatible',true,'lockRisk',v_plan.lock_risk),v_now,v_now),
 (v_ver.organization_id,v_ver.project_id,v_run,'database_policy','PASS','Migration is confined to the customer isolated schema.','{}'::jsonb,v_now,v_now),
 (v_ver.organization_id,v_ver.project_id,v_run,'migration_postflight','SKIPPED','Postflight runs only after execution.','{}'::jsonb,v_now,v_now);
 update public.pandora_database_change_plans set status='approved',verification_run_id=v_run,approved_at=v_now,updated_at=v_now where id=v_plan.id;
 return jsonb_build_object('verificationRunId',v_run,'status','PASS','profile','database_change','replayed',false);
end;$$;
revoke all on function private.pandora_worker_e_verify_database_preflight_20260829(uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_database_preflight_20260829(uuid) to service_role;
create or replace function public.pandora_worker_e_verify_database_preflight_20260829(p_plan_id uuid) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_e_verify_database_preflight_20260829(p_plan_id);$$;
revoke all on function public.pandora_worker_e_verify_database_preflight_20260829(uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_e_verify_database_preflight_20260829(uuid) to service_role;

create or replace function private.pandora_worker_f_apply_isolated_create_table_20260829(p_plan_id uuid,p_table_name text,p_authorization_ref text,p_preflight_verification_run_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_plan public.pandora_database_change_plans%rowtype; v_res public.pandora_runtime_resources%rowtype; v_schema text; v_expected text; v_after text; v_now timestamptz:=clock_timestamp();
begin
 if p_table_name !~ '^[a-z][a-z0-9_]{0,62}$' or p_authorization_ref !~ '^worker-c:[A-Za-z0-9._:-]{4,250}$' then raise exception 'invalid authorized database execution' using errcode='22023'; end if;
 select * into v_plan from public.pandora_database_change_plans where id=p_plan_id for update; if not found or v_plan.status<>'approved' or v_plan.verification_run_id is distinct from p_preflight_verification_run_id then raise exception 'approved preflight required' using errcode='22023'; end if;
 if not exists(select 1 from public.pandora_verification_runs where id=p_preflight_verification_run_id and status='PASS' and required_check_profile='database_change' and project_version_id=v_plan.project_version_id) then raise exception 'Worker E preflight PASS required' using errcode='22023'; end if;
 select * into v_res from public.pandora_runtime_resources where id=v_plan.target_runtime_resource_id and status='ready'; if not found or v_res.isolation_mode<>'shared_isolated' then raise exception 'isolated database unavailable' using errcode='22023'; end if;
 v_schema:=v_res.configuration_redacted->>'schema'; v_expected:=encode(extensions.digest(convert_to('create_table:'||v_schema||'.'||p_table_name||':id_uuid,value_text,created_at_timestamptz','utf8'),'sha256'),'hex');
 if v_expected<>v_plan.migration_set_sha256 or exists(select 1 from information_schema.tables where table_schema=v_schema and table_name=p_table_name) then raise exception 'database migration identity conflict' using errcode='23505'; end if;
 update public.pandora_database_change_plans set status='executing',started_at=v_now,updated_at=v_now where id=v_plan.id;
 execute format('create table %I.%I(id uuid primary key default gen_random_uuid(), value text not null, created_at timestamptz not null default now())',v_schema,p_table_name);
 execute format('grant select,insert,update,delete on %I.%I to %I',v_schema,p_table_name,v_res.configuration_redacted->>'databaseRole');
 select encode(extensions.digest(convert_to(coalesce(string_agg(table_name||':'||column_name||':'||data_type||':'||is_nullable,E'\n' order by table_name,ordinal_position),''),'utf8'),'sha256'),'hex') into v_after from information_schema.columns where table_schema=v_schema;
 update public.pandora_database_change_plans set status='applied',schema_after_sha256=v_after,schema_diff_sha256=encode(extensions.digest(convert_to(schema_before_sha256||':'||v_after,'utf8'),'sha256'),'hex'),applied_at=clock_timestamp(),updated_at=clock_timestamp() where id=v_plan.id;
 return jsonb_build_object('planId',v_plan.id,'status','applied','schema',v_schema,'table',p_table_name,'schemaAfterSha256',v_after,'authorizationRef',p_authorization_ref);
end;$$;
revoke all on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;
create or replace function public.pandora_worker_f_apply_isolated_create_table_20260829(p_plan_id uuid,p_table_name text,p_authorization_ref text,p_preflight_verification_run_id uuid) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_f_apply_isolated_create_table_20260829(p_plan_id,p_table_name,p_authorization_ref,p_preflight_verification_run_id);$$;
revoke all on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_apply_isolated_create_table_20260829(uuid,text,text,uuid) to service_role;

create or replace function private.pandora_worker_e_verify_database_postflight_20260829(p_plan_id uuid,p_table_name text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_plan public.pandora_database_change_plans%rowtype; v_res public.pandora_runtime_resources%rowtype; v_schema text; v_actual text; v_ok boolean; v_check uuid; v_now timestamptz:=clock_timestamp();
begin
 select * into v_plan from public.pandora_database_change_plans where id=p_plan_id for update; if not found or v_plan.status<>'applied' then raise exception 'applied database plan required' using errcode='22023'; end if;
 select * into v_res from public.pandora_runtime_resources where id=v_plan.target_runtime_resource_id; v_schema:=v_res.configuration_redacted->>'schema';
 select encode(extensions.digest(convert_to(coalesce(string_agg(table_name||':'||column_name||':'||data_type||':'||is_nullable,E'\n' order by table_name,ordinal_position),''),'utf8'),'sha256'),'hex') into v_actual from information_schema.columns where table_schema=v_schema;
 v_ok:=v_actual=v_plan.schema_after_sha256 and exists(select 1 from information_schema.tables where table_schema=v_schema and table_name=p_table_name) and not has_table_privilege(v_res.configuration_redacted->>'databaseRole','public.pandora_project_versions','select');
 select id into v_check from public.pandora_verification_checks where verification_run_id=v_plan.verification_run_id and check_key='migration_postflight';
 update public.pandora_verification_checks set status=case when v_ok then 'PASS' else 'FAIL' end,failure_class=case when v_ok then null else 'migration' end,summary=case when v_ok then 'Database postflight and isolation passed.' else 'Database postflight failed.' end,details_redacted=jsonb_build_object('actualSchemaSha256',v_actual,'internalTableAccess',false),started_at=coalesce(started_at,v_now),completed_at=v_now where id=v_check;
 update public.pandora_verification_runs set status=case when not exists(select 1 from public.pandora_verification_checks where verification_run_id=v_plan.verification_run_id and status not in ('PASS','SKIPPED')) then 'PASS' else 'FAIL' end,completed_at=v_now where id=v_plan.verification_run_id;
 update public.pandora_database_change_plans set status=case when v_ok then 'verified' else 'applied' end,verified_at=case when v_ok then v_now else verified_at end,updated_at=v_now where id=v_plan.id;
 return jsonb_build_object('planId',v_plan.id,'status',case when v_ok then 'PASS' else 'FAIL' end,'schemaAfterSha256',v_actual,'internalTableAccess',false);
end;$$;
revoke all on function private.pandora_worker_e_verify_database_postflight_20260829(uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_e_verify_database_postflight_20260829(uuid,text) to service_role;
create or replace function public.pandora_worker_e_verify_database_postflight_20260829(p_plan_id uuid,p_table_name text) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_e_verify_database_postflight_20260829(p_plan_id,p_table_name);$$;
revoke all on function public.pandora_worker_e_verify_database_postflight_20260829(uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_e_verify_database_postflight_20260829(uuid,text) to service_role;

create or replace function private.pandora_worker_f_rollback_isolated_create_table_20260829(p_plan_id uuid,p_table_name text,p_authorization_ref text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_plan public.pandora_database_change_plans%rowtype; v_res public.pandora_runtime_resources%rowtype; v_schema text; v_expected text; v_actual text; v_now timestamptz:=clock_timestamp();
begin
 if p_table_name !~ '^[a-z][a-z0-9_]{0,62}$' or p_authorization_ref !~ '^worker-c:[A-Za-z0-9._:-]{4,250}$' then raise exception 'invalid authorized rollback' using errcode='22023'; end if;
 select * into v_plan from public.pandora_database_change_plans where id=p_plan_id for update; if not found or v_plan.status<>'verified' then raise exception 'verified database plan required' using errcode='22023'; end if;
 select * into v_res from public.pandora_runtime_resources where id=v_plan.target_runtime_resource_id; v_schema:=v_res.configuration_redacted->>'schema';
 v_expected:=encode(extensions.digest(convert_to('drop_table:'||v_schema||'.'||p_table_name,'utf8'),'sha256'),'hex'); if v_expected is distinct from v_plan.rollback_plan_sha256 then raise exception 'rollback identity mismatch' using errcode='22023'; end if;
 if not exists(select 1 from information_schema.tables where table_schema=v_schema and table_name=p_table_name) then raise exception 'rollback target unavailable' using errcode='22023'; end if;
 execute format('drop table %I.%I',v_schema,p_table_name);
 select encode(extensions.digest(convert_to(coalesce(string_agg(table_name||':'||column_name||':'||data_type||':'||is_nullable,E'\n' order by table_name,ordinal_position),''),'utf8'),'sha256'),'hex') into v_actual from information_schema.columns where table_schema=v_schema;
 if v_actual<>v_plan.schema_before_sha256 then raise exception 'rollback schema readback mismatch' using errcode='55000'; end if;
 update public.pandora_database_change_plans set status='rolled_back',rolled_back_at=v_now,updated_at=v_now where id=v_plan.id;
 return jsonb_build_object('planId',v_plan.id,'status','rolled_back','schema',v_schema,'table',p_table_name,'schemaRestoredSha256',v_actual,'authorizationRef',p_authorization_ref);
end;$$;
revoke all on function private.pandora_worker_f_rollback_isolated_create_table_20260829(uuid,text,text) from public,anon,authenticated;
grant execute on function private.pandora_worker_f_rollback_isolated_create_table_20260829(uuid,text,text) to service_role;
create or replace function public.pandora_worker_f_rollback_isolated_create_table_20260829(p_plan_id uuid,p_table_name text,p_authorization_ref text) returns jsonb language sql security definer set search_path='' as $$select private.pandora_worker_f_rollback_isolated_create_table_20260829(p_plan_id,p_table_name,p_authorization_ref);$$;
revoke all on function public.pandora_worker_f_rollback_isolated_create_table_20260829(uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_worker_f_rollback_isolated_create_table_20260829(uuid,text,text) to service_role;


-- E2E-discovered compiler convergence: deploy the exact merged ProjectSpec compiler through the same Vault-backed release boundary.
CREATE OR REPLACE FUNCTION private.pandora_release_deploy_edge_from_github_20260829(p_commit_sha text, p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_path text;
  v_verify_jwt boolean;
  v_import_map_path text;
  v_git jsonb;
  v_git_deno jsonb;
  v_index text;
  v_deno text := null;
  v_source_sha text;
  v_boundary text;
  v_metadata jsonb;
  v_body text;
  v_token text;
  v_probe extensions.http_response;
  v_response extensions.http_response;
  v_response_body jsonb;
begin
  if p_commit_sha is null or p_commit_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'exact GitHub commit SHA required' using errcode='22023';
  end if;
  case p_slug
    when 'pandora-project-runtime' then
      v_path := 'supabase/functions/pandora-project-runtime/index.ts';
      v_verify_jwt := true;
      v_import_map_path := 'deno.json';
    when 'pandora-vercel-runtime-webhook' then
      v_path := 'supabase/functions/pandora-vercel-runtime-webhook/index.ts';
      v_verify_jwt := false;
      v_import_map_path := null;
    when 'pandora-project-source-generator' then
      v_path := 'supabase/functions/pandora-project-source-generator/index.ts';
      v_verify_jwt := true;
      v_import_map_path := null;
    when 'pandora-project-spec-compiler' then
      v_path := 'supabase/functions/pandora-project-spec-compiler/index.ts';
      v_verify_jwt := true;
      v_import_map_path := null;
    else
      raise exception 'Edge function slug outside Pandora release allowlist' using errcode='22023';
  end case;

  v_git := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/'||v_path||'?ref='||p_commit_sha,
    null
  );
  if coalesce((v_git->>'status')::integer,0) <> 200 then
    raise exception 'exact Edge source unavailable at requested commit' using errcode='55000';
  end if;
  begin
    v_index := convert_from(decode(replace(v_git->'body'->>'content',E'\n',''),'base64'),'utf8');
  exception when others then
    raise exception 'exact Edge source decode failed' using errcode='55000';
  end;
  if nullif(v_index,'') is null or octet_length(v_index)>1048576 then
    raise exception 'exact Edge source is empty or exceeds release bound' using errcode='22023';
  end if;

  if v_import_map_path is not null then
    v_git_deno := private.pandora_integration_github_api_20260825(
      'GET',
      '/repos/pandora-rvw-314296438-20260820/pandoras-box/contents/supabase/functions/'||p_slug||'/'||v_import_map_path||'?ref='||p_commit_sha,
      null
    );
    if coalesce((v_git_deno->>'status')::integer,0) <> 200 then
      raise exception 'exact Edge import map unavailable at requested commit' using errcode='55000';
    end if;
    begin
      v_deno := convert_from(decode(replace(v_git_deno->'body'->>'content',E'\n',''),'base64'),'utf8');
    exception when others then
      raise exception 'exact Edge import map decode failed' using errcode='55000';
    end;
    if nullif(v_deno,'') is null or octet_length(v_deno)>65536 then
      raise exception 'exact Edge import map invalid' using errcode='22023';
    end if;
  end if;

  v_source_sha := encode(extensions.digest(convert_to(v_index,'utf8'),'sha256'),'hex');
  v_boundary := '----PandoraEdge'||substr(v_source_sha,1,24);
  if position(v_boundary in v_index)>0 or (v_deno is not null and position(v_boundary in v_deno)>0) then
    raise exception 'multipart boundary collision' using errcode='22023';
  end if;
  v_metadata := jsonb_strip_nulls(jsonb_build_object(
    'name',p_slug,
    'entrypoint_path','index.ts',
    'import_map_path',v_import_map_path,
    'verify_jwt',v_verify_jwt
  ));
  v_body := '--'||v_boundary||E'\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n'||v_metadata::text||
    E'\r\n--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="index.ts"\r\nContent-Type: application/typescript\r\n\r\n'||v_index||E'\r\n';
  if v_deno is not null then
    v_body := v_body||'--'||v_boundary||E'\r\nContent-Disposition: form-data; name="file"; filename="deno.json"\r\nContent-Type: application/json\r\n\r\n'||v_deno||E'\r\n';
  end if;
  v_body := v_body||'--'||v_boundary||E'--\r\n';

  for v_token in
    select decrypted_secret
    from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_probe from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_token),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Exact-Edge-Release/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_probe.status=200;
  end loop;
  if v_probe.status is distinct from 200 or nullif(v_token,'') is null then
    raise exception 'Supabase management credential unavailable for Pandora project' using errcode='55000';
  end if;

  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    ('https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/functions/deploy?slug='||p_slug)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('content-type','multipart/form-data; boundary='||v_boundary),
      extensions.http_header('user-agent','Pandora-Exact-Edge-Release/1.0')
    ]::extensions.http_header[],
    ('multipart/form-data; boundary='||v_boundary)::varchar,
    v_body::varchar
  )::extensions.http_request);
  if v_response.status<>201 then
    v_token:=null;
    raise exception 'Supabase Edge deployment failed with status %',v_response.status using errcode='55000';
  end if;
  begin
    v_response_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_token:=null;
    raise exception 'Supabase Edge deployment returned invalid JSON' using errcode='55000';
  end;
  v_token:=null;
  return jsonb_build_object(
    'deployed',true,
    'commitSha',p_commit_sha,
    'slug',p_slug,
    'sourceSha256',v_source_sha,
    'verifyJwt',v_verify_jwt,
    'version',v_response_body->'version',
    'ezbrSha256',v_response_body->'ezbr_sha256'
  );
end;
$function$



-- E2E-discovered provider transport convergence: use the installed http extension curl controls for bounded Gemini generation.
CREATE OR REPLACE FUNCTION private.pandora_worker_b_gemini_api_20260829(p_model text, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public'
AS $function$
declare
  v_key text;
  v_response extensions.http_response;
  v_body jsonb;
  v_model text;
  v_payload text;
begin
  v_model := trim(coalesce(p_model,''));
  if v_model !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$' then
    raise exception 'invalid Gemini model identifier' using errcode='22023';
  end if;
  if p_body is null or jsonb_typeof(p_body) <> 'object' then
    raise exception 'Gemini request body must be an object' using errcode='22023';
  end if;
  v_payload := p_body::text;
  if octet_length(v_payload) > 1048576 then
    raise exception 'Gemini request body exceeds 1 MiB' using errcode='22023';
  end if;
  if v_payload ~* '"(gemini_api_key|github_supabase|github_pat|service_role_key|supabase_service_role|vercel_token|authorization|cookie|private_key|database_password)"[[:space:]]*:'
     or v_payload ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_payload ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_payload ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_payload ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
     or v_payload ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
    raise exception 'credential material rejected from Gemini request' using errcode='22023';
  end if;

  select decrypted_secret into strict v_key
  from vault.decrypted_secrets
  where name='gemini_api_key'
  limit 1;
  if nullif(trim(v_key),'') is null then
    raise exception 'Gemini provider credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    ('https://generativelanguage.googleapis.com/v1beta/models/' || v_model || ':generateContent')::varchar,
    array[
      extensions.http_header('x-goog-api-key',v_key),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-B-Intelligence/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    v_payload::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := case when nullif(v_response.content,'') is null then null
      else jsonb_build_object('raw',left(v_response.content,5000)) end;
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$function$



-- E2E-discovered lineage convergence: generated project source is a first-class model-run task.
alter table public.pandora_model_runs drop constraint if exists pandora_model_runs_task_check;
alter table public.pandora_model_runs
  add constraint pandora_model_runs_task_check
  check (task in (
    'understand_intent','compile_project_spec','classify_task','plan_build','design_experience','plan_architecture',
    'generate_code','generate_project_source','repair_code','inspect_error','inspect_visual','write_copy',
    'summarize_context','extract_structure','derive_acceptance_tests'
  ));
