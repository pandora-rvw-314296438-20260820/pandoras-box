create or replace function public.pandora_plp_supabase_inventory_20260917()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','vault','extensions','public'
as $function$
declare
  v_name text;
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
  v_out jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  foreach v_name in array array['mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat'] loop
    v_token:=null;
    select decrypted_secret into v_token from vault.decrypted_secrets where name=v_name limit 1;
    if nullif(v_token,'') is null then
      v_out:=v_out||jsonb_build_array(jsonb_build_object('accountSlot',v_name,'status','credential_missing'));
      continue;
    end if;
    select * into v_response from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects'::varchar,
      array[extensions.http_header('authorization','Bearer '||v_token),extensions.http_header('accept','application/json'),extensions.http_header('user-agent','Pandora-PLP-Discovery/1.0')]::extensions.http_header[],
      null::varchar,null::varchar
    )::extensions.http_request);
    v_token:=null;
    if v_response.status<>200 then
      v_out:=v_out||jsonb_build_array(jsonb_build_object('accountSlot',v_name,'status','http_'||v_response.status));
      continue;
    end if;
    v_body:=v_response.content::jsonb;
    for v_item in select value from jsonb_array_elements(v_body) loop
      v_out:=v_out||jsonb_build_array(jsonb_build_object('accountSlot',v_name,'id',v_item->>'id','ref',v_item->>'ref','name',v_item->>'name','organizationId',v_item->>'organization_id','region',v_item->>'region','status',v_item->>'status'));
    end loop;
  end loop;
  return v_out;
end
$function$;
