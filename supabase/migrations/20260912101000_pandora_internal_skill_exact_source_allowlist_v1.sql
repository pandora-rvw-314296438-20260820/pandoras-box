-- Pandora internal skill exact-source allowlist v1
-- Extends Worker E exact-source review to Pandora's canonical skill files only.
-- The canonical repository exception is path-restricted and does not grant model or execution authority.

create or replace function private.pandora_worker_e_exact_source_v2(
  p_repository text,
  p_commit text,
  p_path text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private, extensions
as $$
declare
  v_response extensions.http_response;
  v_url text;
  v_text text;
begin
  if p_repository not in (
    'pandora-rvw-314296438-20260820/awesome-claude-skills',
    'pandora-rvw-314296438-20260820/the-book-of-secret-knowledge',
    'pandora-rvw-314296438-20260820/pandoras-box'
  ) then
    raise exception 'source repository is outside the trusted mirror allowlist' using errcode='42501';
  end if;

  if p_repository='pandora-rvw-314296438-20260820/pandoras-box'
     and coalesce(p_path,'') !~ '^\.agents/skills/[A-Za-z0-9._-]+/SKILL\.md$' then
    raise exception 'canonical Pandora source path is outside the trusted skill allowlist' using errcode='42501';
  end if;

  if coalesce(p_commit,'') !~ '^[0-9a-f]{40}$'
     or length(coalesce(p_path,'')) not between 1 and 500
     or coalesce(p_path,'') !~ '^[A-Za-z0-9._/-]+$'
     or p_path like '%..%' or p_path like '/%' then
    raise exception 'invalid exact-source locator' using errcode='22023';
  end if;

  v_url := 'https://raw.githubusercontent.com/' || p_repository || '/' || p_commit || '/' || p_path;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS','30000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS','5000');
  select * into v_response from extensions.http((
    'GET'::extensions.http_method,
    v_url::varchar,
    array[extensions.http_header('user-agent','Pandora-Worker-E-Exact-Source/2.1')]::extensions.http_header[],
    null::varchar,
    null::varchar
  )::extensions.http_request);
  if v_response.status<>200 then
    return jsonb_build_object('status',v_response.status,'sha256',null,'bytes',0,'content',null);
  end if;
  v_text := coalesce(v_response.content,'');
  if octet_length(v_text)>350000 then
    raise exception 'exact-source file exceeds Worker E review bound' using errcode='54000';
  end if;
  return jsonb_build_object(
    'status',v_response.status,
    'sha256',encode(extensions.digest(convert_to(v_text,'UTF8'),'sha256'),'hex'),
    'bytes',octet_length(v_text),
    'content',v_text
  );
end;
$$;

revoke all on function private.pandora_worker_e_exact_source_v2(text,text,text) from public, anon, authenticated, service_role;
grant execute on function private.pandora_worker_e_exact_source_v2(text,text,text) to postgres;

comment on function private.pandora_worker_e_exact_source_v2(text,text,text)
is 'Exact pinned Worker E source readback. External trusted mirrors retain their existing scope; canonical pandoras-box is allowed only for .agents/skills/<id>/SKILL.md. PostgreSQL administrator only.';
