-- Forward-only Worker D→F ledger/state repair discovered by live bounded Storage recovery.\nCREATE OR REPLACE FUNCTION private.pandora_finalize_runtime_bundle_20260829(p_project_version_id uuid, p_build_job_id uuid, p_build_step_id uuid, p_bundle text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'vault', 'extensions', 'public', 'storage'
AS $function$
declare
  v_version public.pandora_project_versions%rowtype;
  v_job public.pandora_build_jobs%rowtype;
  v_step public.pandora_build_job_steps%rowtype;
  v_payload jsonb;
  v_files jsonb;
  v_entry jsonb;
  v_file text;
  v_prev_file text := null;
  v_decoded bytea;
  v_file_sha text;
  v_total_bytes bigint := 0;
  v_has_index boolean := false;
  v_bundle_sha text;
  v_bundle_bytes bigint;
  v_source_kind text;
  v_source_ref text;
  v_source_commit text;
  v_storage_path text;
  v_pat text;
  v_management extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_upload extensions.http_response;
  v_readback extensions.http_response;
  v_artifact_id uuid;
  v_artifact_version_id uuid;
  v_existing_digest text;
  v_existing_root uuid;
  v_existing_artifact_version uuid;
  v_now timestamptz := clock_timestamp();
begin
  if p_project_version_id is null or p_build_job_id is null or p_build_step_id is null then
    raise exception 'exact build lineage required' using errcode='22023';
  end if;
  if p_bundle is null or octet_length(p_bundle)<2 or octet_length(p_bundle)>26214400 then
    raise exception 'runtime bundle size outside bound' using errcode='22023';
  end if;
  begin
    v_payload := p_bundle::jsonb;
  exception when others then
    raise exception 'runtime bundle JSON invalid' using errcode='22023';
  end;
  if jsonb_typeof(v_payload)<>'object'
     or v_payload->>'kind'<>'pandora.runtime-bundle.v1'
     or coalesce((v_payload->>'schemaVersion')::integer,0)<>1 then
    raise exception 'runtime bundle schema unsupported' using errcode='22023';
  end if;

  select * into v_version from public.pandora_project_versions where id=p_project_version_id for update;
  if not found then raise exception 'project version not found' using errcode='22023'; end if;
  select * into v_job from public.pandora_build_jobs where id=p_build_job_id for update;
  if not found then raise exception 'build job not found' using errcode='22023'; end if;
  select * into v_step from public.pandora_build_job_steps where id=p_build_step_id for update;
  if not found then raise exception 'build step not found' using errcode='22023'; end if;

  if v_version.organization_id<>v_job.organization_id or v_version.project_id<>v_job.project_id
     or v_step.organization_id<>v_job.organization_id or v_step.project_id<>v_job.project_id
     or v_step.build_job_id<>v_job.id
     or v_job.target_project_version_id is distinct from v_version.id
     or v_version.build_job_id is distinct from v_job.id
     or v_version.project_spec_id is distinct from v_job.project_spec_id then
    raise exception 'runtime bundle durable lineage mismatch' using errcode='22023';
  end if;
  if v_step.status<>'succeeded' then
    raise exception 'successful Worker D build step required' using errcode='22023';
  end if;
  if v_job.status not in ('claimed','running','waiting_verification') then
    raise exception 'build job state cannot finalize runtime bundle' using errcode='22023';
  end if;
  if v_version.lifecycle_status not in ('draft','built','verification_pending','verified','preview_ready') then
    raise exception 'project version state cannot bind runtime bundle' using errcode='22023';
  end if;

  v_source_kind := v_version.source_kind;
  v_source_ref := v_version.source_ref;
  v_source_commit := v_version.source_commit;
  if v_payload->>'projectVersionId'<>v_version.id::text
     or v_payload->>'buildJobId'<>v_job.id::text
     or v_payload->>'sourceKind'<>v_source_kind
     or v_payload->>'sourceRef'<>v_source_ref
     or nullif(v_payload->>'sourceCommit','') is distinct from v_source_commit then
    raise exception 'runtime bundle source lineage mismatch' using errcode='22023';
  end if;
  if v_source_kind='git_commit' and (v_source_commit is null or v_source_ref<>v_source_commit) then
    raise exception 'git source identity invalid' using errcode='22023';
  end if;
  if v_source_kind='artifact_snapshot' and (v_source_commit is not null or v_source_ref<>v_version.id::text) then
    raise exception 'artifact snapshot identity invalid' using errcode='22023';
  end if;

  v_files := v_payload->'files';
  if jsonb_typeof(v_files)<>'array' or jsonb_array_length(v_files)<1 or jsonb_array_length(v_files)>1000 then
    raise exception 'runtime bundle files invalid' using errcode='22023';
  end if;
  for v_entry in select value from jsonb_array_elements(v_files)
  loop
    if jsonb_typeof(v_entry)<>'object' then raise exception 'runtime file invalid' using errcode='22023'; end if;
    v_file := nullif(v_entry->>'file','');
    if v_file is null or length(v_file)>512 or left(v_file,1)='/' or right(v_file,1)='/'
       or position(E'\\' in v_file)>0
       or position('?' in v_file)>0 or position('#' in v_file)>0
       or exists (select 1 from unnest(string_to_array(v_file,'/')) as seg(part) where part in ('','.', '..') or length(part)>255) then
      raise exception 'runtime file path invalid' using errcode='22023';
    end if;
    if v_prev_file is not null and v_prev_file collate "C" >= v_file collate "C" then
      raise exception 'runtime files not canonical' using errcode='22023';
    end if;
    v_prev_file := v_file;
    if v_file='index.html' then v_has_index:=true; end if;
    if v_entry->>'encoding'<>'base64' or nullif(v_entry->>'data','') is null then
      raise exception 'runtime file encoding invalid' using errcode='22023';
    end if;
    begin
      v_decoded := decode(v_entry->>'data','base64');
    exception when others then
      raise exception 'runtime file base64 invalid' using errcode='22023';
    end;
    if replace(encode(v_decoded,'base64'),E'\n','')<>v_entry->>'data' then
      raise exception 'runtime file base64 noncanonical' using errcode='22023';
    end if;
    if octet_length(v_decoded)>10485760 then raise exception 'runtime file too large' using errcode='22023'; end if;
    v_total_bytes:=v_total_bytes+octet_length(v_decoded);
    if v_total_bytes>26214400 then raise exception 'runtime bundle decoded files too large' using errcode='22023'; end if;
    v_file_sha:=encode(extensions.digest(v_decoded,'sha256'),'hex');
    if v_entry->>'sha256'<>v_file_sha or coalesce((v_entry->>'byteSize')::bigint,-1)<>octet_length(v_decoded) then
      raise exception 'runtime file digest or size mismatch' using errcode='22023';
    end if;
  end loop;
  if not v_has_index then raise exception 'runtime bundle entrypoint missing' using errcode='22023'; end if;

  v_bundle_bytes:=octet_length(p_bundle);
  v_bundle_sha:=encode(extensions.digest(convert_to(p_bundle,'utf8'),'sha256'),'hex');
  v_storage_path:='runtime/'||v_version.project_id::text||'/'||v_version.id::text||'/'||v_bundle_sha||'.json';

  -- Idempotent durable replay: a source_snapshot root is the authorized build input and may be replaced exactly once by the runtime bundle.
  v_existing_root:=v_version.root_artifact_version_id;
  v_existing_digest:=v_version.artifact_digest_sha256;
  if v_existing_root is not null or v_existing_digest is not null then
    if v_existing_root is not null and v_existing_digest is null
       and exists (
         select 1
         from public.pandora_artifact_versions av
         join public.pandora_artifacts a on a.id=av.artifact_id
         where av.id=v_existing_root
           and av.organization_id=v_version.organization_id
           and av.project_id=v_version.project_id
           and a.organization_id=v_version.organization_id
           and a.project_id=v_version.project_id
           and a.artifact_kind='source_snapshot'
       ) then
      -- Worker C authorized the exact source root; Worker D may now replace it with the exact runtime output.
      null;
    else
      if v_existing_root is null or v_existing_digest is distinct from v_bundle_sha then
        raise exception 'project version already bound to different runtime artifact' using errcode='23505';
      end if;
      select id into v_existing_artifact_version
      from public.pandora_artifact_versions
      where id=v_existing_root and organization_id=v_version.organization_id and project_id=v_version.project_id
        and content_sha256=v_bundle_sha and storage_provider='supabase_storage'
        and storage_bucket='pandora-build-artifacts' and storage_path=v_storage_path;
      if v_existing_artifact_version is null then
        raise exception 'existing runtime artifact binding drifted' using errcode='55000';
      end if;
      return jsonb_build_object('replayed',true,'projectVersionId',v_version.id,'buildJobId',v_job.id,
        'artifactVersionId',v_existing_artifact_version,'artifactDigest',v_bundle_sha,'byteSize',v_bundle_bytes,
        'storageProvider','supabase_storage','storageBucket','pandora-build-artifacts','storagePath',v_storage_path);
    end if;
  end if;

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

  select * into v_upload from extensions.http((
    'POST'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/pandora-build-artifacts/'||v_storage_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('x-upsert','false'),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    'application/json'::varchar,p_bundle::varchar
  )::extensions.http_request);
  if v_upload.status not in (200,201,409) then
    if not (
      v_upload.status=400
      and coalesce((v_upload.content::jsonb)->>'code','')='KeyAlreadyExists'
      and coalesce((v_upload.content::jsonb)->>'statusCode','')='409'
    ) then
      v_service_role:=null;
      raise exception 'runtime artifact storage upload failed with status %',v_upload.status using errcode='55000';
    end if;
  end if;
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
  if v_readback.status<>200 or octet_length(coalesce(v_readback.content,''))<>v_bundle_bytes
     or encode(extensions.digest(convert_to(coalesce(v_readback.content,''),'utf8'),'sha256'),'hex')<>v_bundle_sha then
    raise exception 'runtime artifact storage readback mismatch' using errcode='55000';
  end if;

  insert into public.pandora_artifacts(organization_id,project_id,logical_key,artifact_kind)
  values(v_version.organization_id,v_version.project_id,'runtime-bundle:'||v_version.id::text,'runtime_bundle')
  on conflict(project_id,logical_key) do nothing;
  select id into v_artifact_id from public.pandora_artifacts
  where project_id=v_version.project_id and logical_key='runtime-bundle:'||v_version.id::text and artifact_kind='runtime_bundle';
  if v_artifact_id is null then raise exception 'runtime artifact logical-key collision' using errcode='23505'; end if;

  select id,content_sha256 into v_existing_artifact_version,v_existing_digest
  from public.pandora_artifact_versions where artifact_id=v_artifact_id order by version desc limit 1;
  if v_existing_artifact_version is not null then
    if v_existing_digest<>v_bundle_sha then raise exception 'runtime artifact already has different content' using errcode='23505'; end if;
    v_artifact_version_id:=v_existing_artifact_version;
  else
    insert into public.pandora_artifact_versions(
      organization_id,project_id,artifact_id,parent_version_id,version,content_sha256,byte_size,media_type,
      storage_provider,storage_bucket,storage_path,produced_by_build_step_id,provenance_redacted
    ) values (
      v_version.organization_id,v_version.project_id,v_artifact_id,null,1,v_bundle_sha,v_bundle_bytes,'application/json',
      'supabase_storage','pandora-build-artifacts',v_storage_path,v_step.id,
      jsonb_strip_nulls(jsonb_build_object(
        'buildJobId',v_job.id,'buildStepId',v_step.id,'projectVersionId',v_version.id,
        'projectSpecId',v_version.project_spec_id,'sourceArtifactVersionId',v_existing_root,'sourceKind',v_source_kind,'sourceRef',v_source_ref,'sourceCommit',v_source_commit,
        'finalizedAt',v_now,'schemaVersion','pandora.runtime-bundle.v1'
      ))
    ) returning id into v_artifact_version_id;
  end if;

  update public.pandora_project_versions
  set root_artifact_version_id=v_artifact_version_id,
      artifact_digest_sha256=v_bundle_sha,
      lifecycle_status=case when lifecycle_status='draft' then 'built' else lifecycle_status end
  where id=v_version.id and (root_artifact_version_id is null or root_artifact_version_id=v_existing_root) and artifact_digest_sha256 is null;
  if not found then raise exception 'project version artifact compare-and-set failed' using errcode='40001'; end if;

  if v_job.status='claimed' then
    update public.pandora_build_jobs
    set status='running',current_stage='building',heartbeat_at=v_now,updated_at=v_now
    where id=v_job.id and status='claimed';
    if not found then raise exception 'build job claimed-to-running compare-and-set failed' using errcode='40001'; end if;
  end if;

  update public.pandora_build_jobs
  set status='waiting_verification',current_stage='verifying',lease_owner=null,lease_token_sha256=null,lease_expires_at=null,
      heartbeat_at=v_now,updated_at=v_now
  where id=v_job.id and status in ('claimed','running','waiting_verification');
  if not found then raise exception 'build job finalization compare-and-set failed' using errcode='40001'; end if;

  return jsonb_build_object('replayed',false,'projectVersionId',v_version.id,'buildJobId',v_job.id,
    'buildStepId',v_step.id,'artifactId',v_artifact_id,'artifactVersionId',v_artifact_version_id,
    'artifactDigest',v_bundle_sha,'byteSize',v_bundle_bytes,'sourceKind',v_source_kind,'sourceRef',v_source_ref,
    'storageProvider','supabase_storage','storageBucket','pandora-build-artifacts','storagePath',v_storage_path,
    'verificationState','waiting_verification');
end;
$function$


comment on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) is 'Worker D to Worker F exact runtime bundle finalizer. Runtime artifact version chains remain same-artifact; cross-artifact source lineage is immutable provenance. Claimed jobs advance through running before waiting_verification.';
