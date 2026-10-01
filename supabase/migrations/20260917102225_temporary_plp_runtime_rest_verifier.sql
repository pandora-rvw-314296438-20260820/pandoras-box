create or replace function private.verify_plp_runtime_rest_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_pat text;
  v_keys extensions.http_response;
  v_key text;
  v_rest extensions.http_response;
begin
  select decrypted_secret into v_pat from vault.decrypted_secrets where name='mcpmaster_supabase_account_1_pat' limit 1;
  if v_pat is null then return jsonb_build_object('ok',false,'stage','management_credential'); end if;
  select * into v_keys from extensions.http((
    'GET'::extensions.http_method,
    'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
    array[extensions.http_header('Accept','application/json'),extensions.http_header('Authorization','Bearer '||v_pat)]::extensions.http_header[],
    'application/json'::varchar,null::varchar)::extensions.http_request);
  if v_keys.status<>200 then return jsonb_build_object('ok',false,'stage','api_keys','status',v_keys.status); end if;
  select coalesce(x->>'api_key',x->>'value',x->>'key') into v_key
  from jsonb_array_elements(case when jsonb_typeof(v_keys.content::jsonb)='array' then v_keys.content::jsonb else coalesce((v_keys.content::jsonb)->'keys','[]'::jsonb) end) x
  where x->>'name'='service_role' and coalesce((x->>'disabled')::boolean,false)=false limit 1;
  if v_key is null then return jsonb_build_object('ok',false,'stage','service_role_key'); end if;
  select * into v_rest from extensions.http((
    'GET'::extensions.http_method,
    'https://jcyqixttuebxqqfkjonq.supabase.co/rest/v1/backend_meta?select=key,value'::varchar,
    array[
      extensions.http_header('Accept','application/json'),
      extensions.http_header('apikey',v_key),
      extensions.http_header('Authorization','Bearer '||v_key),
      extensions.http_header('Accept-Profile','plp_runtime')
    ]::extensions.http_header[],
    'application/json'::varchar,null::varchar)::extensions.http_request);
  v_pat:=null; v_key:=null;
  return jsonb_build_object('ok',v_rest.status=200,'status',v_rest.status,'rowCount',case when v_rest.status=200 then jsonb_array_length(v_rest.content::jsonb) else null end,'contentType',(select h.value from unnest(v_rest.headers) h where lower(h.field)='content-type' limit 1));
end $fn$;
revoke all on function private.verify_plp_runtime_rest_20260917() from public,anon,authenticated;
