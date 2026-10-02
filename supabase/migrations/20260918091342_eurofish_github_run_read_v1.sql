
create or replace function public.pandora_eurofish_github_run_read_v1(p_run_id bigint, p_view text default 'run')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_view text := lower(trim(coalesce(p_view,'run')));
  v_path text;
begin
  if p_run_id <= 0 then
    raise exception 'pandora_eurofish_run_id_invalid' using errcode='22023';
  end if;

  if v_view='run' then
    v_path := '/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/' || p_run_id::text;
  elsif v_view='jobs' then
    v_path := '/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/' || p_run_id::text || '/jobs?per_page=100';
  else
    raise exception 'pandora_eurofish_run_view_not_allowed' using errcode='22023';
  end if;

  return private.pandora_integration_github_api_20260825('GET',v_path,null::jsonb);
end;
$$;

revoke all on function public.pandora_eurofish_github_run_read_v1(bigint,text) from public;
grant execute on function public.pandora_eurofish_github_run_read_v1(bigint,text) to authenticated, service_role;
;
