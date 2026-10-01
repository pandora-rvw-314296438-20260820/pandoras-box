create or replace function private.pandora_enterprise_e2e_invoke_20260917()
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','public','private','extensions'
as $$
declare
  v_key text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select config_value into strict v_key
  from public.pandora_runtime_provider_configs
  where provider='enterprise_e2e' and config_key='one_time_key' and active=true;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','240000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');

  select * into v_response
  from extensions.http((
    'POST'::extensions.http_method,
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-analyze-repair-20260830'::varchar,
    array[
      extensions.http_header('x-pandora-e2e-key',v_key),
      extensions.http_header('content-type','application/json')
    ]::extensions.http_header[],
    'application/json'::varchar,
    '{}'::varchar
  )::extensions.http_request);

  begin
    v_body := coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb);
  exception when others then
    v_body := jsonb_build_object('ok',false,'code','INVALID_E2E_RESPONSE');
  end;

  return jsonb_build_object(
    'httpStatus',v_response.status,
    'ok',coalesce((v_body->>'ok')::boolean,false),
    'sourceSha',v_body->>'sourceSha',
    'fileCount',v_body->>'fileCount',
    'totalBytes',v_body->>'totalBytes',
    'deploymentId',v_body#>>'{deployment,id}',
    'deploymentUrl',v_body#>>'{deployment,url}',
    'deploymentStatus',v_body#>>'{deployment,status}',
    'errorCode',v_body->>'code'
  );
end;
$$;
revoke all on function private.pandora_enterprise_e2e_invoke_20260917() from public,anon,authenticated;
grant execute on function private.pandora_enterprise_e2e_invoke_20260917() to service_role;
