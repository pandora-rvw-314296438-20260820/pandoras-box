
create or replace function public.pandora_qwen3_apk_signed_url()
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, extensions
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_location text;
begin
  select decrypted_secret
    into strict v_token
  from vault.decrypted_secrets
  where name='Github_supabase'
  limit 1;

  select * into v_response
  from extensions.http((
    'HEAD'::extensions.http_method,
    'https://api.github.com/repos/pandora-rvw-314296438-20260820/pandoras-box/releases/assets/575958829'::varchar,
    array[
      extensions.http_header('authorization','Bearer '||v_token),
      extensions.http_header('accept','application/octet-stream'),
      extensions.http_header('x-github-api-version','2026-03-10'),
      extensions.http_header('user-agent','Pandora-Qwen3-APK-Redirect/1.0')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  if v_response.status <> 302 then
    raise exception 'GitHub asset redirect unavailable (status %)', v_response.status;
  end if;

  select h.value
    into v_location
  from unnest(v_response.headers) h
  where lower(h.field)='location'
  limit 1;

  if v_location is null or v_location !~ '^https://release-assets\.githubusercontent\.com/' then
    raise exception 'GitHub asset redirect missing or invalid';
  end if;

  return v_location;
end;
$$;

revoke all on function public.pandora_qwen3_apk_signed_url() from public, anon, authenticated;
grant execute on function public.pandora_qwen3_apk_signed_url() to service_role, postgres;

