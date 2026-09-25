-- FB-004: READ ONLY. Primary project jcyqixttuebxqqfkjonq.
-- Explicit platform inventory; no token values, customer content or raw metadata.
-- Replace manifest identities only after authoritative provisioning/review.
select jsonb_build_object(
  'observedAt', now(),
  'projects', (select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'organization_id',organization_id,'project_key',project_key,
    'repository',repository,'status',status)), '[]'::jsonb)
    from public.pandora_projects where id='ee282126-3f61-4058-8c92-2fedbfcecf1f'),
  'registries', (select coalesce(jsonb_agg(jsonb_build_object(
    'project_id',project_id,'organization_id',organization_id,
    'canonical_repository',canonical_repository)), '[]'::jsonb)
    from private.project_canonical_registry where project_id='ee282126-3f61-4058-8c92-2fedbfcecf1f'),
  'tenants', (select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'organization_id',organization_id,'project_id',project_id,'status',status,
    'workspace_key',workspace_key) order by workspace_key), '[]'::jsonb)
    from public.pandora_tracking_tenants where id in
      ('326b51af-0445-4e96-bf31-d346bab05220','44df4ab7-c25e-45b0-a230-db976ba8ccf9')),
  'campaigns', (select coalesce(jsonb_agg(jsonb_build_object(
    'slug',slug,'tenant_id',tenant_id,'provider',provider,
    'provider_campaign_bound',nullif(btrim(provider_campaign_id),'') is not null)), '[]'::jsonb)
    from public.pandora_tracking_campaigns where slug='pandora-meta-main'),
  'metaConnections', (select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id',organization_id,'credential_reference_present',user_token_secret_id is not null)), '[]'::jsonb)
    from private.pandora_meta_connections where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0')
) as primary_snapshot;
