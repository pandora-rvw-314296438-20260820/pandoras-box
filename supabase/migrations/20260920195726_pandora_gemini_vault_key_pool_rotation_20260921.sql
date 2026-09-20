-- Pandora Gemini Vault key-pool failover.
-- Keeps credentials in Vault, tries the currently healthy slot first, and
-- fails over across every configured Gemini API key without returning secrets.

create or replace function private.pandora_worker_b_gemini_api_20260829(
  p_model text,
  p_body jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'private', 'vault', 'extensions', 'public'
as $function$
declare
  v_key_name text;
  v_key text;
  v_response extensions.http_response;
  v_body jsonb;
  v_best_response extensions.http_response;
  v_best_body jsonb;
  v_model text;
  v_payload text;
  v_attempted integer := 0;
  v_key_names constant text[] := array[
    'Gemini_api3',
    'gemini_api_key',
    'gemini_api',
    'gemini_api1',
    'Gemini_api2'
  ];
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

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','90000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  foreach v_key_name in array v_key_names loop
    v_key := null;
    select decrypted_secret
      into v_key
      from vault.decrypted_secrets
     where name = v_key_name
     limit 1;

    if nullif(trim(v_key),'') is null then
      continue;
    end if;

    begin
      select *
        into v_response
        from extensions.http((
          'POST'::extensions.http_method,
          ('https://generativelanguage.googleapis.com/v1beta/models/' || v_model || ':generateContent')::varchar,
          array[
            extensions.http_header('x-goog-api-key',v_key),
            extensions.http_header('content-type','application/json'),
            extensions.http_header('user-agent','Pandora-Worker-B-Intelligence/1.1')
          ]::extensions.http_header[],
          'application/json'::varchar,
          v_payload::varchar
        )::extensions.http_request);
      v_attempted := v_attempted + 1;
    exception when others then
      continue;
    end;

    begin
      v_body := nullif(v_response.content,'')::jsonb;
    exception when others then
      v_body := case when nullif(v_response.content,'') is null then null
        else jsonb_build_object('raw',left(v_response.content,5000)) end;
    end;

    if v_response.status between 200 and 299 then
      return jsonb_build_object(
        'status',v_response.status,
        'contentType',v_response.content_type,
        'body',v_body
      );
    end if;

    if v_response.status not in (401,403,429) and v_response.status < 500 then
      return jsonb_build_object(
        'status',v_response.status,
        'contentType',v_response.content_type,
        'body',v_body
      );
    end if;

    if v_best_response.status is null
       or (v_best_response.status in (401,403)
           and v_response.status not in (401,403)) then
      v_best_response := v_response;
      v_best_body := v_body;
    end if;
  end loop;

  if v_attempted = 0 then
    raise exception 'Gemini provider credential unavailable' using errcode='55000';
  end if;

  if v_best_response.status is not null then
    return jsonb_build_object(
      'status',v_best_response.status,
      'contentType',v_best_response.content_type,
      'body',v_best_body
    );
  end if;

  return jsonb_build_object(
    'status',503,
    'contentType','application/json',
    'body',jsonb_build_object(
      'error',jsonb_build_object(
        'status','UNAVAILABLE',
        'message','Gemini transport unavailable across configured credential slots.'
      )
    )
  );
end;
$function$;

revoke all on function private.pandora_worker_b_gemini_api_20260829(text,jsonb) from public, anon, authenticated;
grant execute on function private.pandora_worker_b_gemini_api_20260829(text,jsonb) to service_role;

alter function public.pandora_worker_b_gemini_request_20260829(text,jsonb)
  set statement_timeout = '90s';
