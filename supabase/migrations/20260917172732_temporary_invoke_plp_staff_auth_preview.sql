create or replace function private.invoke_plp_staff_auth_preview_20260918()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions'
as $fn$
declare v_secret text; v_response extensions.http_response; v_body jsonb;
begin
 select decrypted_secret into strict v_secret from vault.decrypted_secrets where name='plp_staff_auth_preview_run_20260918' limit 1;
 perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','180000');
 perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','10000');
 select * into v_response from extensions.http((
  'POST'::extensions.http_method,
  'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-final-repair-20260830'::varchar,
  array[extensions.http_header('content-type','application/json'),extensions.http_header('x-pandora-run-secret',v_secret),extensions.http_header('user-agent','Pandora-PLP-StaffAuthPreview-Invoker/1.0')]::extensions.http_header[],
  'application/json'::varchar,'{}'::varchar)::extensions.http_request);
 v_secret:=null;
 begin v_body:=coalesce(nullif(v_response.content,'')::jsonb,'{}'::jsonb); exception when others then v_body:=jsonb_build_object('ok',false,'error','invalid_edge_response'); end;
 return jsonb_build_object('status',v_response.status,'body',v_body);
end $fn$;
revoke all on function private.invoke_plp_staff_auth_preview_20260918() from public,anon,authenticated;
