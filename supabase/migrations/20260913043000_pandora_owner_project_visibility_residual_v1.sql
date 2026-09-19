-- Recording 4998 residual owner visibility cleanup v1
-- Explicitly hide only the remaining verified internal/test rows that escaped v1.

update public.projectos_projects
set config = coalesce(config,'{}'::jsonb) || jsonb_build_object(
      'ownerVisible',false,
      'ownerVisibilityReason','internal_control_or_verification'
    ),
    updated_at = updated_at
where status <> 'archived'
  and coalesce((config->>'ownerVisible')::boolean,false) is not true
  and (
    project_key in (
      'pandora-rvw-314296438-20260820-76374545',
      'pandoras-box-and-pandoras-box-memory-4cc63040',
      'test-test-test-784ac0f8'
    )
    or (
      project_key = 'pandoras-box'
      and repository is null
      and lower(name) = 'pandoras box'
    )
  );
