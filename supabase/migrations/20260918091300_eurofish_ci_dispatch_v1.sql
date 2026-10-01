
create or replace function public.pandora_eurofish_github_ci_dispatch_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_ref jsonb;
  v_sha text;
begin
  v_ref := private.pandora_integration_github_api_20260825(
    'GET',
    '/repos/pandora-rvw-314296438-20260820/pandoras-box/git/ref/heads/enterprise-ui-business-1',
    null::jsonb
  );
  v_sha := v_ref #>> '{body,object,sha}';

  if v_sha is null or v_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_eurofish_ci_branch_unreadable' using errcode='22023';
  end if;

  return jsonb_build_object(
    'branchSha', v_sha,
    'dispatch', private.pandora_integration_github_api_20260825(
      'POST',
      '/repos/pandora-rvw-314296438-20260820/pandoras-box/actions/workflows/pandora-mobile-integration.yml/dispatches',
      jsonb_build_object('ref','enterprise-ui-business-1')
    )
  );
end;
$$;

revoke all on function public.pandora_eurofish_github_ci_dispatch_v1() from public;
grant execute on function public.pandora_eurofish_github_ci_dispatch_v1() to authenticated, service_role;

