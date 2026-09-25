-- FB-004: READ ONLY. Memory project ivmvufhcsezyhczzondn.
-- A shared repository is NOT a tenant selector. Return it to expose ambiguity.
-- Do not select HMAC material, user records, OIDC subjects or candidate contents.
select jsonb_build_object(
  'observedAt', now(),
  'projects', (select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'project_key',project_key,'github_owner',github_owner,
    'github_repository',github_repository,'memory_namespace',memory_namespace,
    'lifecycle_status',lifecycle_status) order by id), '[]'::jsonb)
    from public.pandora_projects where id='7c686cbd-d968-49d5-86cc-918f5e777bd2'
      or (github_owner='pandora-rvw-314296438-20260820' and github_repository='pandoras-box')),
  'principals', (select coalesce(jsonb_agg(jsonb_build_object(
    'principal_key',principal_key,'environment',environment,'allowed_namespaces',allowed_namespaces,
    'scopes',scopes,'is_active',is_active)), '[]'::jsonb)
    from public.pandora_service_principals where principal_key='pandora-mcpmaster-production'),
  'grants', (select coalesce(jsonb_agg(jsonb_build_object(
    'project_id',project_id,'principal_key',principal_key,'environment',environment,
    'is_active',is_active,'revoked',revoked_at is not null,'can_read',can_read,
    'can_propose',can_propose,'can_approve',can_approve,'allowed_record_types',allowed_record_types)
    order by environment), '[]'::jsonb)
    from public.pandora_project_grants where principal_key='pandora-mcpmaster-production'
      and project_id='7c686cbd-d968-49d5-86cc-918f5e777bd2')
) as memory_snapshot;
