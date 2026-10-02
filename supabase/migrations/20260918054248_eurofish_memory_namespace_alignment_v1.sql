
alter table eurofish.memory_outbox alter column memory_namespace set default 'real_life';
update eurofish.memory_outbox set memory_namespace='real_life' where memory_namespace='enterprise:eurofish';

create or replace function public.pandora_eurofish_workspace_v1(p_surface text default 'overview')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,eurofish
as $$
declare
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_profile jsonb;
  v_facts jsonb;
  v_sources jsonb;
begin
  if v_surface not in ('overview','commercial','import_operations','aquaculture','floriculture','customers','suppliers','compliance','finance','evidence','integrations','admin') then
    v_surface := 'overview';
  end if;

  select jsonb_build_object(
    'businessKey',business_key,'displayName',display_name,'legalName',legal_name,'timezone',timezone,
    'currency',currency,'address',address_text,'status',profile_status,'observedAt',source_observed_at
  ) into v_profile
  from eurofish.business_profile where business_key='enterprise-eurofish' limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',fact_key,'label',label,'value',fact_value,'truthStatus',truth_status,'sourceKind',source_kind,
    'sourceName',source_name,'sourceUrl',source_url,'observedAt',observed_at,'verifiedAt',verified_at,'notes',notes
  ) order by fact_key),'[]'::jsonb)
  into v_facts from eurofish.business_facts;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key',source_key,'name',display_name,'type',source_type,'status',status,'lastSuccessAt',last_success_at,
    'lastAttemptAt',last_attempt_at,'message',customer_message
  ) order by source_key),'[]'::jsonb)
  into v_sources from eurofish.source_connections;

  return jsonb_build_object(
    'projectKey','enterprise-eurofish',
    'memoryNamespace','real_life',
    'memoryProjectKey','enterprise-eurofish',
    'surface',v_surface,
    'profile',coalesce(v_profile,'{}'::jsonb),
    'facts',v_facts,
    'sources',v_sources,
    'dataTruth',jsonb_build_object(
      'live','source + sync time','verified','evidence-backed','manual','entered with provenance',
      'stale','last known state is old','notConnected','no authoritative operational source',
      'externalIntelligence','never silently merged into internal truth'
    ),
    'operatingModel',jsonb_build_array(
      'Demand','Quote','Commitment','Supplier','Purchase','Permit','Booking','Flight','Arrival','Inspection',
      'Clearance','Release','Receiving','Condition/Survival','Allocation','Delivery','Invoice','Collection','Outcome'
    ),
    'generatedAt',now()
  );
end $$;

revoke all on function public.pandora_eurofish_workspace_v1(text) from public;
grant execute on function public.pandora_eurofish_workspace_v1(text) to anon, authenticated;
;
