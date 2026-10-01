create or replace function private.test_plp_oidc_gateway_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare
  v_vercel text; v_token_response extensions.http_response; v_oidc text; v_gateway extensions.http_response; v_payload jsonb; v_rows jsonb;
begin
  select decrypted_secret into strict v_vercel from vault.decrypted_secrets where name='vercel' limit 1;
  select * into v_token_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api.vercel.com/v1/projects/prj_4W4GcwFJ3BPA4TnsEfHkmAm7HYeV/token?teamId=team_3yw1CN59ce4pj5SwyQGCAqN3'::varchar,
    array[extensions.http_header('Authorization','Bearer '||v_vercel),extensions.http_header('Content-Type','application/json'),extensions.http_header('Accept','application/json'),extensions.http_header('User-Agent','Pandora-PLP-OIDC-Test/1.0')]::extensions.http_header[],
    'application/json'::varchar,
    '{"source":"pandora-plp-gateway-test"}'::varchar
  )::extensions.http_request);
  if v_token_response.status<>200 then v_vercel:=null; return jsonb_build_object('ok',false,'stage','vercel_oidc_issue','status',v_token_response.status); end if;
  v_oidc:=(v_token_response.content::jsonb)->>'token';
  if nullif(v_oidc,'') is null then v_vercel:=null; return jsonb_build_object('ok',false,'stage','oidc_missing'); end if;
  select * into v_gateway from extensions.http((
    'POST'::extensions.http_method,
    'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-merge-pr162-20260830'::varchar,
    array[extensions.http_header('Authorization','Bearer '||v_oidc),extensions.http_header('Content-Type','application/json'),extensions.http_header('User-Agent','Pandora-PLP-OIDC-Test/1.0')]::extensions.http_header[],
    'application/json'::varchar,
    '{"method":"GET","path":"backend_meta?select=key,value"}'::varchar
  )::extensions.http_request);
  v_oidc:=null; v_vercel:=null;
  if v_gateway.status<>200 then return jsonb_build_object('ok',false,'stage','gateway','status',v_gateway.status,'body',left(coalesce(v_gateway.content,''),300)); end if;
  begin v_rows:=v_gateway.content::jsonb; exception when others then return jsonb_build_object('ok',false,'stage','gateway_json'); end;
  return jsonb_build_object('ok',true,'gatewayStatus',v_gateway.status,'rowCount',jsonb_array_length(v_rows),'backendKey',v_rows#>>'{0,key}','temporaryBackend',coalesce(((v_rows#>'{0,value}')::jsonb->>'temporary_backend')::boolean,false),'schema',(v_rows#>'{0,value}')::jsonb->>'schema','tokenReturned',false);
end $fn$;
revoke all on function private.test_plp_oidc_gateway_20260917() from public,anon,authenticated;
