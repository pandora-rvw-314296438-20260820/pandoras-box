create or replace function public.pandora_plp_promote_20260917()
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
begin
  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='vercel' limit 1;
  select config_value into strict v_team_id from public.pandora_runtime_provider_configs where provider='vercel' and config_key='team_id' and active=true limit 1;
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    ('https://api.vercel.com/v10/projects/prj_4W4GcwFJ3BPA4TnsEfHkmAm7HYeV/promote/dpl_DCvvbcphqFfVPZ7F3tDyeBz2nRfR?teamId='||v_team_id)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/json'),
      extensions.http_header('user-agent','Pandora-PLP-Promote/1.0')
    ]::extensions.http_header[],
    ''::varchar,
    ''::varchar
  )::extensions.http_request);
  v_token:=null;
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then v_body:=null; end;
  return jsonb_build_object('status',v_response.status,'body',v_body);
end
$function$;
