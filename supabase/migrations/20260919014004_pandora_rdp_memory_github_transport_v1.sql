create or replace function public.pandora_rdp_memory_github_request_v1(
  p_method text,
  p_path text,
  p_body jsonb default null::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_method text := upper(trim(coalesce(p_method,'')));
  v_path text := trim(coalesce(p_path,''));
  v_body_text text := coalesce(p_body::text,'');
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box-memory';
  v_result jsonb;
begin
  if v_method not in ('GET','POST','PATCH') then
    raise exception 'pandora_rdp_memory_github_method_not_allowed' using errcode='22023';
  end if;
  if v_path like '%..%' or v_path not like v_prefix || '%' then
    raise exception 'pandora_rdp_memory_github_path_not_allowed' using errcode='22023';
  end if;

  if v_method='GET' then
    if not (
      v_path ~ ('^' || v_prefix || '/git/ref/heads/(main|(?:chatgpt|recovery|repair|fix)/[A-Za-z0-9._%/-]{1,220})$')
      or v_path ~ ('^' || v_prefix || '/git/commits/[0-9a-f]{40}$')
    ) then
      raise exception 'pandora_rdp_memory_github_read_path_not_allowed' using errcode='22023';
    end if;
  elsif v_method='POST' then
    if v_path ~ ('^' || v_prefix || '/git/blobs$') then
      if octet_length(v_body_text) > 6000000 then
        raise exception 'pandora_rdp_memory_github_blob_too_large' using errcode='22023';
      end if;
    elsif v_path ~ ('^' || v_prefix || '/git/(trees|commits)$') then
      if octet_length(v_body_text) > 1000000 then
        raise exception 'pandora_rdp_memory_github_object_too_large' using errcode='22023';
      end if;
    elsif v_path ~ ('^' || v_prefix || '/git/refs$') then
      if coalesce(p_body->>'ref','') !~ '^refs/heads/(chatgpt|recovery|repair|fix)/[A-Za-z0-9._/-]{1,220}$' then
        raise exception 'pandora_rdp_memory_github_ref_not_allowed' using errcode='22023';
      end if;
      if coalesce(p_body->>'sha','') !~ '^[0-9a-f]{40}$' then
        raise exception 'pandora_rdp_memory_github_ref_sha_invalid' using errcode='22023';
      end if;
    else
      raise exception 'pandora_rdp_memory_github_write_path_not_allowed' using errcode='22023';
    end if;
  elsif v_method='PATCH' then
    if v_path !~ ('^' || v_prefix || '/git/refs/heads/(?:chatgpt|recovery|repair|fix)/[A-Za-z0-9._%/-]{1,220}$') then
      raise exception 'pandora_rdp_memory_github_ref_update_not_allowed' using errcode='22023';
    end if;
    if coalesce(p_body->>'sha','') !~ '^[0-9a-f]{40}$' or coalesce((p_body->>'force')::boolean,false) is true then
      raise exception 'pandora_rdp_memory_github_non_fast_forward_forbidden' using errcode='22023';
    end if;
  end if;

  v_result := private.pandora_integration_github_api_20260825(v_method,v_path,p_body);
  return v_result;
end;
$$;

revoke all on function public.pandora_rdp_memory_github_request_v1(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_rdp_memory_github_request_v1(text,text,jsonb) to service_role;
