-- Pandora canonical GitHub transport repository identity correction v2
-- Corrects the pandoras-box-memory installation repository id while preserving
-- fixed repository scope and Vault-backed credential handling.

create or replace function private.pandora_integration_github_api_20260825(
  p_method text,
  p_path text,
  p_body jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, vault, extensions
as $$
declare
  v_token text;
  v_response extensions.http_response;
  v_body jsonb;
  v_method extensions.http_method;
  v_box_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_memory_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_plp_prefix constant text := '/repos/pandora-rvw-314296438-20260820/plp';
begin
  if upper(coalesce(p_method,'')) not in ('GET','POST','PUT','PATCH','DELETE') then
    raise exception 'unsupported GitHub method' using errcode='22023';
  end if;
  if p_path is null or p_path like '%..%' then
    raise exception 'invalid GitHub path' using errcode='22023';
  end if;
  if not (
    p_path ~ ('^' || v_box_prefix || '(/|$)')
    or p_path ~ ('^' || v_memory_prefix || '(/|$)')
    or p_path ~ ('^' || v_plp_prefix || '(/|$)')
    or (upper(p_method)='GET' and p_path ~ '^/user/installations([?].*)?$')
    or (upper(p_method)='PUT' and p_path ~ '^/user/installations/[0-9]+/repositories/(1345495177|1346392092|1358856339)$')
  ) then
    raise exception 'GitHub path is outside the fixed Pandora recovery scope' using errcode='22023';
  end if;

  select decrypted_secret into strict v_token
  from vault.decrypted_secrets
  where name='Github_supabase'
  limit 1;
  if nullif(trim(v_token),'') is null then
    raise exception 'GitHub provider credential unavailable' using errcode='55000';
  end if;

  v_method := upper(p_method)::extensions.http_method;
  select * into v_response
  from extensions.http((
    v_method,
    ('https://api.github.com' || p_path)::varchar,
    array[
      extensions.http_header('authorization','Bearer ' || v_token),
      extensions.http_header('accept','application/vnd.github+json'),
      extensions.http_header('x-github-api-version','2026-03-10'),
      extensions.http_header('user-agent','Pandora-Integration-Transport/1.3'),
      extensions.http_header('content-type','application/json')
    ]::extensions.http_header[],
    case when p_body is null then null else 'application/json' end::varchar,
    case when p_body is null then null else p_body::text end::varchar
  )::extensions.http_request);

  begin
    v_body := nullif(v_response.content,'')::jsonb;
  exception when others then
    v_body := case when nullif(v_response.content,'') is null
      then null
      else jsonb_build_object('raw',left(v_response.content,2000))
    end;
  end;

  return jsonb_build_object(
    'status',v_response.status,
    'contentType',v_response.content_type,
    'body',v_body
  );
end;
$$;

revoke all on function private.pandora_integration_github_api_20260825(text,text,jsonb) from public,anon,authenticated;
grant execute on function private.pandora_integration_github_api_20260825(text,text,jsonb) to service_role;

comment on function private.pandora_integration_github_api_20260825(text,text,jsonb)
is 'Vault-backed fixed-scope Pandora GitHub transport for pandoras-box, pandoras-box-memory, and PLP; canonical repository ids 1345495177, 1346392092, and 1358856339.';
