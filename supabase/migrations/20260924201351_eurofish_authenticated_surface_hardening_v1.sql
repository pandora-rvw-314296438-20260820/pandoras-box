-- Euro-Fish authenticated surface hardening v1.
--
-- The customer workspace already has eurofish.access_memberships and a guarded
-- private workspace RPC. Populate the intended owner/admin access set, apply
-- the same membership boundary to the public workspace RPC, and remove direct
-- authenticated execution from Vault-backed GitHub transport wrappers.

insert into eurofish.access_memberships(user_id,role,active,created_at,updated_at)
select
  m.user_id,
  case m.role::text when 'owner' then 'owner' else 'admin' end,
  true,
  now(),
  now()
from public.memberships m
where m.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
  and m.status::text='active'
  and m.role::text in ('owner','admin')
on conflict (user_id) do update
set role=excluded.role,
    active=true,
    updated_at=now();

create or replace function public.pandora_eurofish_workspace_v1(
  p_surface text default 'overview'::text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','eurofish','auth'
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_surface text := lower(coalesce(nullif(trim(p_surface),''),'overview'));
  v_profile jsonb;
  v_facts jsonb;
  v_sources jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select role into v_role
  from eurofish.access_memberships
  where user_id=v_uid and active=true;

  if v_role is null then
    raise exception 'eurofish access denied' using errcode='42501';
  end if;

  if v_surface not in (
    'overview','commercial','import_operations','aquaculture','floriculture',
    'customers','suppliers','compliance','finance','evidence','integrations','admin'
  ) then
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
    'actorRole',v_role,
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
end;
$$;

revoke all on function public.pandora_eurofish_workspace_v1(text)
from public,anon;
grant execute on function public.pandora_eurofish_workspace_v1(text)
to authenticated,service_role;

do $hardening$
declare
  sig text;
begin
  foreach sig in array array[
    'public.pandora_eurofish_github_request_v1(text,text,jsonb)',
    'public.pandora_eurofish_memory_github_request_v1(text,text,jsonb)',
    'public.pandora_eurofish_github_ci_dispatch_v1()',
    'public.pandora_eurofish_github_ci_read_v1(text)',
    'public.pandora_eurofish_github_ci_rerun_v1(bigint)',
    'public.pandora_eurofish_github_run_read_v1(bigint,text)'
  ]
  loop
    if to_regprocedure(sig) is not null then
      execute format('revoke all on function %s from public, anon, authenticated',sig);
      execute format('grant execute on function %s to service_role',sig);
    end if;
  end loop;
end
$hardening$;

