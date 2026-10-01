create or replace function public.pandora_plp_restore_backend_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions','public'
as $function$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
begin
  select decrypted_secret into strict v_token from vault.decrypted_secrets where name='mcpmaster_supabase_account_1_pat' limit 1;
  select * into v_response from extensions.http((
    'POST'::extensions.http_method,
    'https://api.supabase.com/v1/projects/kywmbyekwgtghkhhurof/restore'::varchar,
    array[extensions.http_header('authorization','Bearer '||v_token),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-PLP-Restore/1.0')]::extensions.http_header[],
    ''::varchar,''::varchar
  )::extensions.http_request);
  v_token:=null;
  begin v_body:=nullif(v_response.content,'')::jsonb; exception when others then v_body:=null; end;
  return jsonb_build_object('status',v_response.status,'body',v_body);
end
$function$;
