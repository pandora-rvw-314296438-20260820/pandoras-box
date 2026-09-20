create or replace function public.pandora_gemini_stream_credential_service_20260901()
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_secret text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'Gemini_api3'
  order by created_at desc
  limit 1;

  if nullif(btrim(v_secret), '') is null then
    raise exception 'GEMINI_STREAM_CREDENTIAL_UNAVAILABLE';
  end if;

  return v_secret;
end;
$function$;

revoke all on function public.pandora_gemini_stream_credential_service_20260901()
  from public, anon, authenticated;
grant execute on function public.pandora_gemini_stream_credential_service_20260901()
  to service_role;

create or replace function private.pandora_worker_e_gemini_api_v2(
  p_model text,
  p_body jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'vault', 'extensions'
as $function$
declare
  v_key text;
  v_response extensions.http_response;
  v_json jsonb;
  v_payload text;
begin
  if p_model not in ('gemini-3-flash-preview','gemini-3.1-flash-lite-preview') then
    raise exception 'Worker E model outside independent-review allowlist' using errcode='42501';
  end if;
  if p_body is null or jsonb_typeof(p_body)<>'object' then
    raise exception 'Worker E Gemini body must be an object' using errcode='22023';
  end if;
  v_payload := p_body::text;
  if octet_length(v_payload)>900000 then
    raise exception 'Worker E Gemini payload exceeds bound' using errcode='54000';
  end if;
  if v_payload ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_payload ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_payload ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_payload ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
     or v_payload ~* 'postgres(ql)?://[^[:space:]:@]+:[^[:space:]@]+@' then
    raise exception 'credential-like material rejected from Worker E review' using errcode='22023';
  end if;

  select decrypted_secret into strict v_key
  from vault.decrypted_secrets
  where name='Gemini_api3'
  limit 1;

  if nullif(trim(v_key),'') is null then
    raise exception 'Gemini reviewer credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','90000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    ('https://generativelanguage.googleapis.com/v1beta/models/'||p_model||':generateContent')::varchar,
    array[
      extensions.http_header('x-goog-api-key',v_key),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Worker-E-Independent-Review/2.1')
    ]::extensions.http_header[],
    'application/json'::varchar,
    v_payload::varchar
  )::extensions.http_request);

  begin
    v_json := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_json:=jsonb_build_object('raw',left(coalesce(v_response.content,''),5000));
  end;

  return jsonb_build_object('status',v_response.status,'body',v_json);
end;
$function$;

revoke all on function private.pandora_worker_e_gemini_api_v2(text,jsonb)
  from public, anon, authenticated;
grant execute on function private.pandora_worker_e_gemini_api_v2(text,jsonb)
  to service_role;
