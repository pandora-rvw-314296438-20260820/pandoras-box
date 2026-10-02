
begin;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('dmci-public-media','dmci-public-media',true,52428800,array['video/mp4']::text[])
on conflict (id) do update
set public=true,
    file_size_limit=excluded.file_size_limit,
    allowed_mime_types=excluded.allowed_mime_types;

create or replace function private.pandora_dmci_public_media_signed_upload_v1(p_object_path text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','vault','extensions','storage'
as $function$
declare
  v_pat text;
  v_management extensions.http_response;
  v_keys jsonb;
  v_service_role text;
  v_signed extensions.http_response;
  v_body jsonb;
  v_role text;
begin
  v_role := coalesce(
    nullif(current_setting('request.jwt.claims', true),'')::jsonb->>'role',
    ''
  );
  if session_user not in ('postgres','service_role','supabase_admin')
     and v_role <> 'service_role' then
    raise exception 'PANDORA_DMCI_MEDIA_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  if coalesce(p_object_path,'') !~ '^dmci-payroll-facility/[a-z0-9][a-z0-9._-]{5,120}\.mp4$' then
    raise exception 'PANDORA_DMCI_MEDIA_PATH_INVALID' using errcode='22023';
  end if;

  for v_pat in
    select decrypted_secret
    from vault.decrypted_secrets
    where name in ('mcpmaster_supabase_account_1_pat','mcpmaster_supabase_account_2_pat')
    order by case name when 'mcpmaster_supabase_account_1_pat' then 1 else 2 end
  loop
    select * into v_management from extensions.http((
      'GET'::extensions.http_method,
      'https://api.supabase.com/v1/projects/jcyqixttuebxqqfkjonq/api-keys?reveal=true'::varchar,
      array[
        extensions.http_header('authorization','Bearer '||v_pat),
        extensions.http_header('accept','application/json'),
        extensions.http_header('user-agent','Pandora-DMCI-Media-Grant/1.0')
      ]::extensions.http_header[],
      null::varchar,
      null::varchar
    )::extensions.http_request);
    exit when v_management.status=200;
  end loop;

  if v_management.status is distinct from 200 then
    v_pat := null;
    raise exception 'PANDORA_DMCI_MEDIA_PROVIDER_KEY_UNAVAILABLE' using errcode='55000';
  end if;

  begin
    v_keys := v_management.content::jsonb;
  exception when others then
    v_pat := null;
    raise exception 'PANDORA_DMCI_MEDIA_KEY_RESPONSE_INVALID' using errcode='55000';
  end;

  select coalesce(x->>'api_key',x->>'value',x->>'key')
  into v_service_role
  from jsonb_array_elements(
    case
      when jsonb_typeof(v_keys)='array' then v_keys
      else coalesce(v_keys->'keys','[]'::jsonb)
    end
  ) x
  where x->>'name'='service_role'
    and coalesce((x->>'disabled')::boolean,false)=false
  limit 1;

  v_pat := null;
  v_keys := null;

  if nullif(v_service_role,'') is null then
    raise exception 'PANDORA_DMCI_MEDIA_SERVICE_ROLE_UNAVAILABLE' using errcode='55000';
  end if;

  select * into v_signed from extensions.http((
    'POST'::extensions.http_method,
    ('https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/upload/sign/dmci-public-media/'||p_object_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_service_role),
      extensions.http_header('apikey',v_service_role),
      extensions.http_header('content-type','application/json'),
      extensions.http_header('x-upsert','true'),
      extensions.http_header('cache-control','no-store'),
      extensions.http_header('user-agent','Pandora-DMCI-Media-Grant/1.0')
    ]::extensions.http_header[],
    'application/json'::varchar,
    '{}'::varchar
  )::extensions.http_request);

  v_service_role := null;

  if v_signed.status not in (200,201) then
    raise exception 'PANDORA_DMCI_MEDIA_SIGN_FAILED_%', v_signed.status using errcode='55000';
  end if;

  begin
    v_body := v_signed.content::jsonb;
  exception when others then
    raise exception 'PANDORA_DMCI_MEDIA_SIGN_RESPONSE_INVALID' using errcode='55000';
  end;

  if nullif(v_body->>'url','') is null then
    raise exception 'PANDORA_DMCI_MEDIA_SIGN_URL_MISSING' using errcode='55000';
  end if;

  return jsonb_build_object(
    'ok',true,
    'bucket','dmci-public-media',
    'path',p_object_path,
    'signedPath',v_body->>'url',
    'publicUrl','https://jcyqixttuebxqqfkjonq.supabase.co/storage/v1/object/public/dmci-public-media/'||p_object_path,
    'expiresInSeconds',7200
  );
end;
$function$;

revoke all on function private.pandora_dmci_public_media_signed_upload_v1(text)
from public, anon, authenticated;

comment on function private.pandora_dmci_public_media_signed_upload_v1(text)
is 'Service-role-only bounded signed-upload grant for DMCI public media. Returns only a short-lived path-scoped upload grant; never returns provider credentials.';

commit;
;
