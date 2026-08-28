do $$
declare
  r record;
begin
  for r in
    select p.oid, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname in (
        'capture_canonical_physical_android_receipt',
        'capture_canonical_vercel_rehearsal_receipt',
        'get_canonical_release_status_without_final_attestations'
      )
  loop
    execute replace(
      r.definition,
      'mcpmaster.vercel.app',
      'pandoras-box-system.vercel.app'
    );
  end loop;
end
$$;

update private.project_canonical_registry
set production_url = 'https://pandoras-box-system.vercel.app',
    config = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            config,
            '{auth,desiredSiteUrl}',
            to_jsonb('https://pandoras-box-system.vercel.app'::text),
            true
          ),
          '{auth,siteUrlCutoverState}',
          to_jsonb('management_api_update_required'::text),
          true
        ),
        '{canonicalAlignment,canonicalProductionUrl}',
        to_jsonb('https://pandoras-box-system.vercel.app'::text),
        true
      ),
      '{canonicalAlignment,state}',
      to_jsonb('domain_cutover_pending_runtime_metadata'::text),
      true
    ) || jsonb_build_object(
      'domainCutover', jsonb_build_object(
        'canonicalUrl', 'https://pandoras-box-system.vercel.app',
        'canonicalHost', 'pandoras-box-system.vercel.app',
        'legacyUrl', 'https://mcpmaster.vercel.app',
        'legacyHost', 'mcpmaster.vercel.app',
        'legacyBehavior', 'compatibility_redirect',
        'runtimeMetadataExpectedResource', 'https://pandoras-box-system.vercel.app/mcp',
        'runtimeMetadataObservedResourceAtCutover', 'https://mcpmaster.vercel.app/mcp',
        'runtimeMetadataState', 'pending_source_runtime_update',
        'authDesiredSiteUrl', 'https://pandoras-box-system.vercel.app',
        'authSiteUrlState', 'management_api_update_required',
        'cutoverRecordedAt', statement_timestamp()
      )
    ),
    updated_at = statement_timestamp()
where vercel_project_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk';

update public.projectos_project_resources r
set canonical_url = 'https://pandoras-box-system.vercel.app',
    binding_state = 'degraded',
    configuration = r.configuration || jsonb_build_object(
      'canonicalAlias', 'pandoras-box-system.vercel.app',
      'legacyAlias', 'mcpmaster.vercel.app',
      'legacyBehavior', 'compatibility_redirect',
      'domainCutoverState', 'runtime_metadata_pending',
      'deployedSourceSha', coalesce(
        (select c.deployed_sha
         from private.project_canonical_registry c
         where c.project_id = r.project_id
         limit 1),
        r.configuration ->> 'deployedSourceSha'
      )
    ),
    updated_at = statement_timestamp()
where r.provider = 'vercel'
  and r.external_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk';

update public.projectos_integration_health h
set status = 'degraded',
    details = h.details || jsonb_build_object(
      'productionUrl', 'https://pandoras-box-system.vercel.app',
      'legacyProductionUrl', 'https://mcpmaster.vercel.app',
      'legacyBehavior', 'compatibility_redirect',
      'canonicalAligned', false,
      'domainCutoverState', 'runtime_metadata_pending',
      'oauthMetadataResource', 'https://mcpmaster.vercel.app/mcp',
      'oauthMetadataExpectedResource', 'https://pandoras-box-system.vercel.app/mcp',
      'health', jsonb_build_object(
        'root', 200,
        'health', 200,
        'apiHealth', 200,
        'mcpGet', 401,
        'automatedReadback', true
      )
    ),
    last_event_at = statement_timestamp(),
    stale_after = statement_timestamp() + interval '12 hours',
    updated_at = statement_timestamp()
where h.provider = 'vercel'
  and h.project_id = (
    select c.project_id
    from private.project_canonical_registry c
    where c.vercel_project_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
    limit 1
  );

update public.projectos_integration_health h
set status = 'degraded',
    details = h.details || jsonb_build_object(
      'desiredSiteUrl', 'https://pandoras-box-system.vercel.app',
      'currentSiteUrl', coalesce(h.details ->> 'siteUrl', 'https://mcpmaster.vercel.app'),
      'siteUrlCutoverState', 'management_api_update_required',
      'domainCutoverState', 'supabase_auth_pending_site_url_update'
    ),
    last_event_at = statement_timestamp(),
    stale_after = statement_timestamp() + interval '12 hours',
    updated_at = statement_timestamp()
where h.provider = 'supabase_auth'
  and h.project_id = (
    select c.project_id
    from private.project_canonical_registry c
    where c.vercel_project_id = 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk'
    limit 1
  );