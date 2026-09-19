-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

update private.projectos_event_contracts
set allowed_properties = array(
  select distinct property_key
  from unnest(
    allowed_properties || array[
      'environment','release_sha','app_version','deployment_id','event_schema_version','source_repo','privacy_tier',
      'route_group','screen','feature_key','outcome','status','success','error_code','duration_ms',
      'funnel_step','entrypoint','channel','device_type','browser','os','action_key','target_section','source_path'
    ]::text[]
  ) as property_key
), updated_at = now()
where organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'
  and product_key='fxpass'
  and active;
