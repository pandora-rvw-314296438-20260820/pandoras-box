-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

-- Remove PostgreSQL's implicit PUBLIC execution from every ProjectOS
-- SECURITY DEFINER function, then restore only the intended role grants.

create or replace function public.projectos_get_registry(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not private.is_org_member(p_organization_id) then
    raise exception using errcode = '42501', message = 'projectos_forbidden';
  end if;

  select jsonb_build_object(
    'organizationId', p_organization_id,
    'policy', (
      select to_jsonb(policy_row)
      from public.projectos_policies policy_row
      where policy_row.organization_id = p_organization_id
    ),
    'projects', coalesce(jsonb_agg(jsonb_build_object(
      'id', project.id,
      'key', project.project_key,
      'name', project.name,
      'repository', project.repository,
      'status', project.status,
      'workspacePath', project.workspace_path,
      'resources', coalesce((
        select jsonb_agg(jsonb_build_object(
          'provider', resource.provider,
          'resourceType', resource.resource_type,
          'externalId', resource.external_id,
          'externalName', resource.external_name,
          'environment', resource.environment,
          'canonicalUrl', resource.canonical_url,
          'bindingState', resource.binding_state,
          'configuration', resource.configuration
        ) order by resource.provider, resource.binding_state, resource.external_name)
        from public.projectos_project_resources resource
        where resource.project_id = project.id
      ), '[]'::jsonb),
      'tasks', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', task.id,
          'key', task.task_key,
          'title', task.title,
          'status', task.status,
          'riskClass', task.risk_class,
          'completionCriteria', task.completion_criteria,
          'currentBranch', task.current_branch,
          'currentPullRequestNumber', task.current_pr_number,
          'currentHeadSha', task.current_head_sha,
          'builderAgent', task.builder_agent,
          'builderVendor', task.builder_vendor,
          'reviewerAgent', task.reviewer_agent,
          'reviewerVendor', task.reviewer_vendor
        ) order by task.sequence)
        from public.projectos_tasks task
        where task.project_id = project.id
          and task.status <> 'cancelled'
      ), '[]'::jsonb)
    ) order by project.updated_at desc), '[]'::jsonb)
  )
  into v_result
  from public.projectos_projects project
  where project.organization_id = p_organization_id
    and project.status <> 'archived';

  return v_result;
end;
$$;

do $hardening$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'projectos\_%' escape '\'
      and p.prosecdef
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      v_function.signature
    );
    execute format(
      'grant execute on function %s to service_role',
      v_function.signature
    );
  end loop;
end;
$hardening$;

-- Authenticated callers may use only RPCs whose bodies enforce organization
-- membership or an explicit owner/admin/operator role.
grant execute on function public.projectos_accept_intake(uuid,uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.projectos_get_agent_routing_evidence(uuid,text,text,text,text,integer) to authenticated;
grant execute on function public.projectos_get_context(uuid,text,text) to authenticated;
grant execute on function public.projectos_get_dashboard(uuid,text) to authenticated;
grant execute on function public.projectos_get_registry(uuid) to authenticated;
grant execute on function public.projectos_recommend_agents(uuid,text,text,integer) to authenticated;
grant execute on function public.projectos_recompute_project(uuid,text) to authenticated;
grant execute on function public.projectos_register_project(uuid,text,text,text,text,uuid) to authenticated;
grant execute on function public.projectos_upsert_agent_runtime_proof(uuid,text,jsonb) to authenticated;

comment on function public.projectos_get_registry(uuid) is
  'Returns the organization-scoped ProjectOS registry after service-role or membership authorization.';
