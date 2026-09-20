-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_get_registry(
  p_organization_id uuid
) returns jsonb
language sql
security definer
set search_path = public, private, auth, pg_temp
as $$
  select jsonb_build_object(
    'organizationId', p_organization_id,
    'policy', (select to_jsonb(policy_row) from public.projectos_policies policy_row where policy_row.organization_id = p_organization_id),
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
        where task.project_id = project.id and task.status <> 'cancelled'
      ), '[]'::jsonb)
    ) order by project.updated_at desc), '[]'::jsonb)
  )
  from public.projectos_projects project
  where project.organization_id = p_organization_id and project.status <> 'archived';
$$;

grant execute on function public.projectos_get_registry(uuid) to authenticated, service_role;
