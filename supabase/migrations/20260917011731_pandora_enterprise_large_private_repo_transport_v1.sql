create or replace function public.pandora_enterprise_github_request_20260917(
  p_path text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'vault', 'extensions', 'public'
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
  v_base_path text;
  v_url text;
begin
  if p_path is null
     or length(p_path) > 1200
     or p_path like '%..%'
     or p_path ~ E'[\\r\\n]' then
    raise exception 'invalid GitHub path' using errcode='22023';
  end if;

  v_base_path := split_part(p_path, '?', 1);
  if not (
    v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    or v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/languages$'
    or v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/commits/[A-Za-z0-9._/-]+$'
    or v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/git/trees/[0-9a-fA-F]{40}$'
    or v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/git/blobs/[0-9a-fA-F]{40}$'
    or v_base_path ~ '^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/contents(?:/[A-Za-z0-9_@+.%/=-]+)?$'
  ) then
    raise exception 'GitHub path is outside Enterprise repository intake lane'
      using errcode='22023';
  end if;

  if position('?' in p_path) > 0 and not (
    p_path ~ '\?(ref=[A-Za-z0-9._/-]+)$'
    or p_path ~ '\?(recursive=1)$'
  ) then
    raise exception 'unsupported GitHub query' using errcode='22023';
  end if;

  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='Github_supabase'
  limit 1;
  if nullif(trim(v_token),'') is null then
    raise exception 'GitHub provider credential unavailable' using errcode='55000';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  v_url := 'https://api.github.com' || p_path;

  select * into v_response
  from extensions.http((
    'GET'::extensions.http_method,
    v_url::varchar,
    array[
      extensions.http_header('authorization','Bearer ' || v_token),
      extensions.http_header('accept','application/vnd.github+json'),
      extensions.http_header('x-github-api-version','2022-11-28'),
      extensions.http_header('user-agent','Pandora-Enterprise-Repository-Intake/1.1')
    ]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := case when nullif(v_response.content,'') is null then null
      else jsonb_build_object('raw',left(v_response.content,5000)) end;
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$$;

revoke all on function public.pandora_enterprise_github_request_20260917(text)
  from public, anon, authenticated;
grant execute on function public.pandora_enterprise_github_request_20260917(text)
  to service_role;

create or replace function public.pandora_enterprise_vercel_runtime_material_20260917()
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'vault', 'public'
as $$
declare
  v_token text;
  v_team_id text;
begin
  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='vercel'
  limit 1;

  select config_value into strict v_team_id
  from public.pandora_runtime_provider_configs
  where provider='vercel' and config_key='team_id' and active=true
  limit 1;

  if nullif(trim(v_token),'') is null or v_team_id !~ '^team_[A-Za-z0-9]+$' then
    raise exception 'Vercel runtime material unavailable' using errcode='55000';
  end if;

  return jsonb_build_object('token',v_token,'teamId',v_team_id);
end;
$$;

revoke all on function public.pandora_enterprise_vercel_runtime_material_20260917()
  from public, anon, authenticated;
grant execute on function public.pandora_enterprise_vercel_runtime_material_20260917()
  to service_role;

comment on function public.pandora_enterprise_vercel_runtime_material_20260917() is
  'Service-role-only runtime bridge for Pandora Enterprise Vercel file uploads. Never expose to client roles.';
