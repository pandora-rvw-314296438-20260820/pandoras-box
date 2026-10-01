
create or replace function private.pandora_temp_gemini_vault_key_probe_20260921(
  p_key_name text,
  p_model text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','private','vault','extensions'
as $fn$
declare
  v_key text;
  v_resp extensions.http_response;
  v_body jsonb;
begin
  if p_key_name not in ('gemini_api','gemini_api_key','gemini_api1','Gemini_api2','Gemini_api3') then
    raise exception 'KEY_NOT_ALLOWED';
  end if;
  if p_model not in ('gemini-3.5-flash-lite','gemini-3.7-flash','gemini-3.8-flash','gemini-3.1-pro-preview') then
    raise exception 'MODEL_NOT_ALLOWED';
  end if;

  select decrypted_secret into strict v_key
  from vault.decrypted_secrets
  where name = p_key_name
  limit 1;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  select * into v_resp
  from extensions.http((
    'POST'::extensions.http_method,
    ('https://generativelanguage.googleapis.com/v1beta/models/' || p_model || ':generateContent')::varchar,
    array[
      extensions.http_header('x-goog-api-key',v_key),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('user-agent','Pandora-Gemini-Vault-Probe/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    '{"contents":[{"role":"user","parts":[{"text":"Reply with exactly OK"}]}],"generationConfig":{"maxOutputTokens":8,"temperature":0}}'::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_resp.content,'')::jsonb;
  exception when others then
    v_body := jsonb_build_object('raw',left(coalesce(v_resp.content,''),500));
  end;

  return jsonb_build_object(
    'keyName',p_key_name,
    'model',p_model,
    'status',v_resp.status,
    'providerStatus',coalesce(v_body->'error'->>'status','OK'),
    'message',case when v_resp.status between 200 and 299
      then coalesce(v_body->>'modelVersion','success')
      else left(coalesce(v_body->'error'->>'message','unknown error'),220)
    end
  );
end
$fn$;

revoke all on function private.pandora_temp_gemini_vault_key_probe_20260921(text,text) from public, anon, authenticated;
grant execute on function private.pandora_temp_gemini_vault_key_probe_20260921(text,text) to service_role;

