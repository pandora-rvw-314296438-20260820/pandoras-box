create or replace function public.pandora_plp_env_metadata_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions','public'
as $function$
declare
  v_token text;
  v_team_id text;
  v_response extensions.http_response;
  v_body jsonb;
  v_items jsonb;
begin
  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='vercel' limit 1;
  select config_value into strict v_team_id from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true limit 1;
  select * into v_response from extensions.http((
    'GET'::extensions.http_method,
    ('https://api.vercel.com/v9/projects/prj_4W4GcwFJ3BPA4TnsEfHkmAm7HYeV/env?teamId='||v_team_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-PLP-Env-Probe/1.0')
    ]::extensions.http_header[],null::varchar,null::varchar
  )::extensions.http_request);
  v_token:=null;
  if v_response.status<>200 then return jsonb_build_object('ok',false,'status',v_response.status); end if;
  v_body:=v_response.content::jsonb;
  select coalesce(jsonb_agg(jsonb_build_object('key',e->>'key','type',e->>'type','target',e->'target','gitBranch',e->>'gitBranch','hasValue',coalesce(length(e->>'value'),0)>0) order by e->>'key'),'[]'::jsonb)
    into v_items from jsonb_array_elements(coalesce(v_body->'envs','[]'::jsonb)) e;
  return jsonb_build_object('ok',true,'count',jsonb_array_length(v_items),'items',v_items);
end
$function$;
