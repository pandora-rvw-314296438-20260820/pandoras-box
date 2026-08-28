-- Worker B: make the Vault-backed Gemini transport use the pgsql-http curl timeout that is actually honored.\n-- No credential leaves Vault.\n\nCREATE OR REPLACE FUNCTION private.pandora_worker_b_gemini_api_20260829(p_model text, p_body jsonb)
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

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','15000');
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

