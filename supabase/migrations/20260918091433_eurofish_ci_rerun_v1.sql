
create or replace function public.pandora_eurofish_github_ci_rerun_v1(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_run jsonb;
  v_sha text;
  v_branch text;
  v_name text;
begin
  if p_run_id <= 0 then
    raise exception 'pandora_eurofish_run_id_invalid' using errcode='22023';
  end if;

  v_run := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/' || p_run_id::text,
    null::jsonb
  );
  v_sha := v_run #>> '{body,head_sha}';
  v_branch := v_run #>> '{body,head_branch}';
  v_name := v_run #>> '{body,name}';

  if v_sha <> 'e706fb7fbdba06a00fd71b7f890e4fe924b89f26'
     or v_branch <> 'enterprise-ui-business-1'
     or v_name <> 'Pandora mobile exact-source gate' then
    raise exception 'pandora_eurofish_rerun_identity_mismatch' using errcode='22023';
  end if;

  return private.pandora_integration_github_api_20260825(
    'POST',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/runs/' || p_run_id::text || '/rerun',
    null::jsonb
  );
end;
$$;

revoke all on function public.pandora_eurofish_github_ci_rerun_v1(bigint) from public;
grant execute on function public.pandora_eurofish_github_ci_rerun_v1(bigint) to authenticated, service_role;
;
