-- Replace broad Supabase Management API key discovery in static Worker D with the
-- existing one-purpose source-worker trust root and a server-side readback broker.
-- The migration fails closed unless the exact predecessor function definition is present.

DO $migration$
DECLARE
  v_def text;
  v_sha text;
  v_start integer;
  v_end integer;
  v_patch text;
BEGIN
  v_def := pg_get_functiondef(
    'private.pandora_worker_d_finalize_static_web_20260830(uuid)'::regprocedure
  );
  v_sha := encode(
    extensions.digest(convert_to(v_def, 'utf8'), 'sha256'),
    'hex'
  );
  IF v_sha <> 'f6d7149b9e7ba30aff67d08331bfdd97b048bd9934fd2f01dcd1a2f09ef398fd' THEN
    RAISE EXCEPTION 'STATIC_BUILD_PREDECESSOR_IDENTITY_MISMATCH' USING ERRCODE='55000';
  END IF;

  v_start := position(E'  for v_pat in\n' in v_def);
  v_end := position(E'  v_source_text:=v_readback.content;\n' in v_def);
  IF v_start <= 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'STATIC_BUILD_PREDECESSOR_PATCH_BOUNDARY_MISSING' USING ERRCODE='55000';
  END IF;
  v_end := v_end + length(E'  v_source_text:=v_readback.content;\n');

  v_patch := $patch$  select decrypted_secret into v_pat
  from vault.decrypted_secrets
  where name='pandora_source_worker_internal_20260831'
  limit 1;
  if nullif(v_pat,'') is null then
    raise exception 'STATIC_BUILD_STORAGE_AUTH_UNAVAILABLE' using errcode='55000';
  end if;

  select * into v_readback from extensions.http((
    'POST'::extensions.http_method,
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-d-source-readback'::varchar,
    array[
      extensions.http_header('x-pandora-internal-key',v_pat),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('accept','application/json'),
      extensions.http_header('cache-control','no-store')
    ]::extensions.http_header[],
    'application/json'::varchar,
    jsonb_build_object('buildJobId',v_job.id)::text::varchar
  )::extensions.http_request);
  v_pat:=null;

  if v_readback.status<>200 then
    raise exception 'STATIC_BUILD_STORAGE_AUTH_UNAVAILABLE' using errcode='55000';
  end if;
  begin
    v_keys:=v_readback.content::jsonb;
  exception when others then
    raise exception 'STATIC_BUILD_SOURCE_READBACK_INVALID' using errcode='55000';
  end;
  if coalesce((v_keys->>'ok')::boolean,false)<>true
     or v_keys->>'state'<>'source_ready'
     or v_keys->>'buildJobId'<>v_job.id::text
     or v_keys->>'projectVersionId'<>v_version.id::text
     or v_keys->>'artifactVersionId'<>v_source.id::text
     or v_keys->>'sha256'<>v_source.content_sha256
     or coalesce((v_keys->>'byteSize')::bigint,-1)<>v_source.byte_size
     or nullif(v_keys->>'sourceText','') is null then
    raise exception 'STATIC_BUILD_SOURCE_READBACK_MISMATCH' using errcode='55000';
  end if;
  v_source_text:=v_keys->>'sourceText';
  v_keys:=null;
  if octet_length(v_source_text)<>v_source.byte_size
     or encode(extensions.digest(convert_to(v_source_text,'utf8'),'sha256'),'hex')<>v_source.content_sha256 then
    raise exception 'STATIC_BUILD_SOURCE_READBACK_MISMATCH' using errcode='55000';
  end if;
$patch$;

  v_def := overlay(v_def placing v_patch from v_start for (v_end - v_start));
  IF position('api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true' in v_def) > 0
     OR position('pandora-worker-d-source-readback' in v_def) = 0 THEN
    RAISE EXCEPTION 'STATIC_BUILD_PATCH_VERIFICATION_FAILED' USING ERRCODE='55000';
  END IF;
  EXECUTE v_def;
END
$migration$;

REVOKE ALL ON FUNCTION private.pandora_worker_d_finalize_static_web_20260830(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.pandora_worker_d_finalize_static_web_20260830(uuid)
  TO service_role;
