
create or replace function public.pandora_eurofish_github_ci_read_v1(p_path text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_path text := trim(coalesce(p_path,''));
  v_base text := split_part(v_path,'?',1);
  v_query text := case when position('?' in v_path)>0 then split_part(v_path,'?',2) else '' end;
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/pandoras-box';
begin
  if v_path like '%..%' or v_base not like v_prefix || '%' then
    raise exception 'pandora_eurofish_ci_path_not_allowed' using errcode='22023';
  end if;

  if v_base ~ ('^' || v_prefix || '/commits/[0-9a-f]{40}/status$') then
    if v_query <> '' then raise exception 'pandora_eurofish_ci_query_not_allowed' using errcode='22023'; end if;
  elsif v_base ~ ('^' || v_prefix || '/commits/[0-9a-f]{40}/check-runs$') then
    if v_query <> '' then raise exception 'pandora_eurofish_ci_query_not_allowed' using errcode='22023'; end if;
  elsif v_base = v_prefix || '/actions/runs' then
    if v_query !~ '^head_sha=[0-9a-f]{40}(&branch=enterprise-ui-business-1)?(&per_page=(50|100))?$' then
      raise exception 'pandora_eurofish_ci_query_not_allowed' using errcode='22023';
    end if;
  else
    raise exception 'pandora_eurofish_ci_read_not_allowed' using errcode='22023';
  end if;

  return private.pandora_integration_github_api_20260825('GET',v_path,null::jsonb);
end;
$$;

revoke all on function public.pandora_eurofish_github_ci_read_v1(text) from public;
grant execute on function public.pandora_eurofish_github_ci_read_v1(text) to authenticated, service_role;
;
