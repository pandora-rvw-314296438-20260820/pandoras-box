
create or replace function private.pandora_enterprise_vercel_build_events_20260918(
  p_deployment_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','vault','extensions','public'
as $function$
declare
  v_token text;
  v_team_id text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  if p_deployment_id !~ '^dpl_[A-Za-z0-9]+$' then
    raise exception 'invalid deployment id' using errcode='22023';
  end if;

  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true
  limit 1;

  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='vercel'
  limit 1;

  if nullif(trim(v_token),'') is null then
    raise exception 'Vercel provider credential unavailable' using errcode='55000';
  end if;

  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    (
      'https://api.vercel.com/v3/deployments/'||
      p_deployment_id||
      '/events?direction=backward&limit=250&builds=1&teamId='||
      v_team_id
    )::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-Enterprise-Vercel-Diagnostics/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  v_token := null;

  begin
    v_body := coalesce(nullif(v_response.content,'')::jsonb,'[]'::jsonb);
  exception when others then
    v_body := jsonb_build_object(
      'raw',
      left(coalesce(v_response.content,''),20000)
    );
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$function$;

revoke all on function private.pandora_enterprise_vercel_build_events_20260918(text)
from public, anon, authenticated;
grant execute on function private.pandora_enterprise_vercel_build_events_20260918(text)
to service_role;
;
