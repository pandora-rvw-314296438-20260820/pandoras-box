
-- Pandora owner project visibility v1
-- Explicitly keep control-plane/proof/verification projects out of normal owner project lists.

update public.projectos_projects
set config = coalesce(config,'{}'::jsonb) || jsonb_build_object(
      'ownerVisible',false,
      'ownerVisibilityReason','internal_control_or_verification'
    ),
    updated_at = updated_at
where status <> 'archived'
  and coalesce((config->>'ownerVisible')::boolean,false) is not true
  and (
    coalesce(config->>'systemRole','') = 'pandora_control_plane'
    or project_key = 'projectos-inbox'
    or project_key ~ '^worker-[a-z0-9-]*proof'
    or project_key in (
      'provider-integration-verifier',
      'supabase-state-verifier',
      'pandora-alpha-workboard',
      'pandora-memory-maximization',
      'pandora-memory-supabase-source-parity-recovery',
      'mcpmaster-pandoras-box'
    )
    or coalesce(config->>'internal','false') = 'true'
    or coalesce(config->>'disposable','false') = 'true'
    or coalesce(config->>'disposableProof','false') = 'true'
  );

comment on column public.projectos_projects.config is
'Project configuration. ownerVisible=false marks internal control/proof projects that remain available to governance/admin surfaces but are excluded from normal owner project lists.';
