-- Keep Worker-D runtime artifact persistence inside the existing one-purpose
-- source-worker service-role boundary. The database no longer discovers a
-- service-role key through long-lived Supabase Management API PATs.

begin;

do $migration$
declare
  v_def text;
  v_start integer;
  v_end integer;
  v_patch text;
begin
  select pg_get_functiondef(
    'private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text)'::regprocedure
  ) into v_def;

  if position('application/vnd.pandora.runtime-bundle+json' in v_def) = 0 then
    if position(
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'
      in v_def
    ) = 0 then
      raise exception 'RUNTIME_ARTIFACT_BROKER_PREDECESSOR_MISSING' using errcode='55000';
    end if;

    v_start := position(
      E'  -- Resolve the control project''s service-role key through Vault-held Management credentials.\n'
      in v_def
    );
    v_end := position(E'  insert into public.pandora_artifacts(' in v_def);
    if v_start <= 0 or v_end <= v_start then
      raise exception 'RUNTIME_ARTIFACT_BROKER_PATCH_BOUNDARY_MISSING' using errcode='55000';
    end if;

    v_patch := $patch$  -- Persist through the internal source-worker service-role boundary.
  select decrypted_secret into v_pat
  from vault.decrypted_secrets
  where name='pandora_source_worker_internal_20260831'
  limit 1;
  if nullif(v_pat,'') is null then
    raise exception 'runtime artifact storage broker credential unavailable' using errcode='55000';
  end if;

  select * into v_upload from extensions.http((
    'POST'::extensions.http_method,
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-source-convergence-worker'::varchar,
    array[
      extensions.http_header('x-pandora-internal-key',v_pat),
      extensions.http_header('content-type','application/vnd.pandora.runtime-bundle+json'),
      extensions.http_header('accept','application/json'),
      extensions.http_header('cache-control','no-store'),
      extensions.http_header('x-pandora-build-job-id',v_job.id::text),
      extensions.http_header('x-pandora-build-step-id',v_step.id::text),
      extensions.http_header('x-pandora-runtime-sha256',v_bundle_sha),
      extensions.http_header('x-pandora-runtime-byte-size',v_bundle_bytes::text)
    ]::extensions.http_header[],
    'application/vnd.pandora.runtime-bundle+json'::varchar,
    p_bundle::varchar
  )::extensions.http_request);
  v_pat:=null;

  if v_upload.status<>200 then
    raise exception 'runtime artifact storage broker unavailable with status %',v_upload.status using errcode='55000';
  end if;
  begin
    v_keys:=v_upload.content::jsonb;
  exception when others then
    raise exception 'runtime artifact storage broker response invalid' using errcode='55000';
  end;
  if coalesce((v_keys->>'ok')::boolean,false)<>true
     or v_keys->>'state'<>'runtime_persisted'
     or v_keys->>'buildJobId'<>v_job.id::text
     or v_keys->>'buildStepId'<>v_step.id::text
     or v_keys->>'projectVersionId'<>v_version.id::text
     or v_keys->>'sha256'<>v_bundle_sha
     or coalesce((v_keys->>'byteSize')::bigint,-1)<>v_bundle_bytes
     or v_keys->>'storageProvider'<>'supabase_storage'
     or v_keys->>'storageBucket'<>'pandora-build-artifacts'
     or v_keys->>'storagePath'<>v_storage_path then
    raise exception 'runtime artifact storage broker mismatch' using errcode='55000';
  end if;
  v_keys:=null;

$patch$;

    v_def := overlay(v_def placing v_patch from v_start for (v_end - v_start));
    if position('api-keys?reveal=true' in v_def) > 0
       or position('mcpmaster_supabase_account_1_pat' in v_def) > 0
       or position('mcpmaster_supabase_account_2_pat' in v_def) > 0
       or position('application/vnd.pandora.runtime-bundle+json' in v_def) = 0
       or position('pandora-source-convergence-worker' in v_def) = 0 then
      raise exception 'RUNTIME_ARTIFACT_BROKER_PATCH_VERIFY_FAILED' using errcode='55000';
    end if;
    execute v_def;
  end if;

  select pg_get_functiondef(
    'private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text)'::regprocedure
  ) into v_def;
  if position('api-keys?reveal=true' in v_def) > 0
     or position('mcpmaster_supabase_account_1_pat' in v_def) > 0
     or position('mcpmaster_supabase_account_2_pat' in v_def) > 0
     or position('application/vnd.pandora.runtime-bundle+json' in v_def) = 0
     or position('x-pandora-runtime-sha256' in v_def) = 0
     or position('pandora-source-convergence-worker' in v_def) = 0 then
    raise exception 'RUNTIME_ARTIFACT_BROKER_FINAL_VERIFY_FAILED' using errcode='55000';
  end if;
end
$migration$;

revoke all on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text)
  to service_role;

comment on function private.pandora_finalize_runtime_bundle_20260829(uuid,uuid,uuid,text) is
'Persists exact Worker-D runtime bundles through the existing source-worker service-role broker; no Supabase Management API key discovery occurs in the build path.';

commit;
