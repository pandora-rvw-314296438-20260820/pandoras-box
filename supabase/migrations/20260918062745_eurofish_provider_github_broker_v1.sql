
create or replace function public.pandora_eurofish_github_request_v1(
  p_method text,
  p_path text,
  p_body jsonb default null::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_method text := upper(trim(coalesce(p_method,'')));
  v_path text := trim(coalesce(p_path,''));
  v_base_path text := split_part(v_path,'?',1);
  v_query text := case when position('?' in v_path) > 0 then split_part(v_path,'?',2) else '' end;
  v_body_text text := coalesce(p_body::text,'');
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_result jsonb;
begin
  if v_method not in ('GET','POST','PATCH') then
    raise exception 'pandora_eurofish_github_method_not_allowed' using errcode='22023';
  end if;

  if v_path like '%..%' or v_base_path not like v_prefix || '%' then
    raise exception 'pandora_eurofish_github_path_not_allowed' using errcode='22023';
  end if;

  if v_method='GET' then
    if not (
      v_base_path in (
        v_prefix || '/git/ref/heads/main',
        v_prefix || '/git/ref/heads/enterprise-ui-business-1'
      )
      or v_base_path ~ ('^' || v_prefix || '/git/commits/[0-9a-f]{40}$')
      or v_base_path ~ ('^' || v_prefix || '/git/trees/[0-9a-f]{40}$')
      or v_base_path ~ ('^' || v_prefix || '/git/blobs/[0-9a-f]{40}$')
    ) then
      raise exception 'pandora_eurofish_github_read_path_not_allowed' using errcode='22023';
    end if;

    if v_query <> '' and not (
      v_base_path ~ ('^' || v_prefix || '/git/trees/[0-9a-f]{40}$')
      and v_query in ('recursive=1','recursive=true')
    ) then
      raise exception 'pandora_eurofish_github_query_not_allowed' using errcode='22023';
    end if;

  elsif v_method='POST' then
    if v_base_path = v_prefix || '/git/blobs' then
      if octet_length(v_body_text) > 6000000 then
        raise exception 'pandora_eurofish_github_blob_too_large' using errcode='22023';
      end if;
    elsif v_base_path in (v_prefix || '/git/trees', v_prefix || '/git/commits') then
      if octet_length(v_body_text) > 1500000 then
        raise exception 'pandora_eurofish_github_object_too_large' using errcode='22023';
      end if;
    else
      raise exception 'pandora_eurofish_github_write_path_not_allowed' using errcode='22023';
    end if;

  elsif v_method='PATCH' then
    if v_base_path <> v_prefix || '/git/refs/heads/enterprise-ui-business-1' then
      raise exception 'pandora_eurofish_github_ref_update_not_allowed' using errcode='22023';
    end if;
    if coalesce(p_body->>'sha','') !~ '^[0-9a-f]{40}$'
       or coalesce((p_body->>'force')::boolean,false) is true then
      raise exception 'pandora_eurofish_github_non_fast_forward_forbidden' using errcode='22023';
    end if;
  end if;

  v_result := private.pandora_integration_github_api_20260825(v_method,v_path,p_body);
  return v_result;
end;
$$;

revoke all on function public.pandora_eurofish_github_request_v1(text,text,jsonb) from public;
grant execute on function public.pandora_eurofish_github_request_v1(text,text,jsonb) to authenticated, service_role;
;
