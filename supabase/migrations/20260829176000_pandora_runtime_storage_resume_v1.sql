-- Worker F exact private-Storage recovery for an externally committed runtime bundle.
create or replace function private.pandora_resume_runtime_bundle_finalization_20260830(
  p_project_version_id uuid,
  p_build_job_id uuid,
  p_build_step_id uuid,
  p_expected_bundle_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','public','storage'
as $fn$
declare
  v_version public.pandora_project_versions%rowtype;
  v_storage_path text;
  v_pat text;
  v_management extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_readback extensions.http_response;
  v_actual_sha text;
  v_result jsonb;
begin
  if p_project_version_id is null or p_build_job_id is null or p_build_step_id is null
     or p_expected_bundle_sha256 is null or p_expected_bundle_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'exact runtime recovery lineage required' using errcode='22023';
  end if;
  select * into v_version
  from public.pandora_project_versions
  where id=p_project_version_id;
  if not found or v_version.build_job_id is distinct from p_build_job_id then
    raise exception 'runtime recovery version lineage mismatch' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.pandora_build_job_steps
    where id=p_build_step_id and build_job_id=p_build_job_id and status='succeeded'
  ) then
    raise exception 'successful exact build step required for runtime recovery' using errcode='22023';
  end if;
  v_storage_path:='runtime/'||v_version.project_id::text||'/'||v_version.id::text||'/'||p_expected_bundle_sha256||'.json';

-- Resolve the control project's service-role key through Vault-held Management credentials.
  for v_pat in
    select decrypted_secret from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_management from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_pat),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-Runtime-Artifact-Finalizer/1.0')
      ]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    exit when v_management.status=200;
  end loop;
  if v_management.status is distinct from 200 then
    v_pat:=null;
    raise exception 'Supabase management credential unavailable for artifact persistence' using errcode='55000';
  end if;
  begin v_keys:=v_management.content::jsonb; exception when others then v_pat:=null; raise exception 'Supabase API key response invalid' using errcode='55000'; end;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_service_role
  from jsonb_array_elements(case when jsonb_typeof(v_keys)='array' then v_keys else coalesce(v_keys->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  v_pat:=null; v_keys:=null;
  if nullif(v_service_role,'') is null then raise exception 'control project service role unavailable' using errcode='55000'; end if;


  select * into v_readback from extensions.http((
    'GET'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/authenticated/pandora-build-artifacts/'||v_storage_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    null::varchar,null::varchar
  )::extensions.http_request);
  v_service_role:=null;
  if v_readback.status<>200 or octet_length(coalesce(v_readback.content,''))<2
     or octet_length(coalesce(v_readback.content,''))>26214400 then
    raise exception 'runtime recovery object unavailable or outside bound' using errcode='55000';
  end if;
  v_actual_sha:=encode(extensions.digest(convert_to(v_readback.content,'utf8'),'sha256'),'hex');
  if v_actual_sha<>p_expected_bundle_sha256 then
    raise exception 'runtime recovery object digest mismatch' using errcode='55000';
  end if;
  v_result:=private.pandora_finalize_runtime_bundle_20260829(
    p_project_version_id,p_build_job_id,p_build_step_id,v_readback.content
  );
  return jsonb_build_object(
    'recovered',true,
    'expectedBundleSha256',p_expected_bundle_sha256,
    'storagePath',v_storage_path,
    'finalization',v_result
  );
end;
$fn$;

revoke all on function private.pandora_resume_runtime_bundle_finalization_20260830(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_resume_runtime_bundle_finalization_20260830(uuid,uuid,uuid,text) to service_role;

create or replace function public.pandora_resume_runtime_bundle_finalization_20260830(
  p_project_version_id uuid,
  p_build_job_id uuid,
  p_build_step_id uuid,
  p_expected_bundle_sha256 text
)
returns jsonb
language sql
security definer
set search_path=''
as $fn$
  select private.pandora_resume_runtime_bundle_finalization_20260830($1,$2,$3,$4);
$fn$;
revoke all on function public.pandora_resume_runtime_bundle_finalization_20260830(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_resume_runtime_bundle_finalization_20260830(uuid,uuid,uuid,text) to service_role;

comment on function private.pandora_resume_runtime_bundle_finalization_20260830(uuid,uuid,uuid,text) is 'Worker F bounded recovery path for an exact runtime bundle already committed to private Storage before durable finalization completed.';
