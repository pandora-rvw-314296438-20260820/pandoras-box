update plp_runtime.backend_meta
set value = value || jsonb_build_object(
  'canonical_repo','pandora-rvw-314296438-20260820/plp',
  'schema','plp_runtime',
  'github_schema_routing_merge_sha','54f1d3414c38439a578b1aec3652598108067434',
  'service_role_stored_in_vercel',false,
  'credential_strategy','vercel_oidc_to_supabase_edge',
  'updated_at',now()
), updated_at=now()
where key='backend_identity';
