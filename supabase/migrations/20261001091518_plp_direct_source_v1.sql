-- PLP Pandora Direct tenant source v1.
-- This creates a customer-scoped operational source path without claiming an external PMS/OTA connection.

create table if not exists private.plp_direct_source_bindings (
  property_id uuid primary key references public.enterprise_properties(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_key text not null default 'pandora_direct' check (source_key='pandora_direct'),
  active boolean not null default false,
  activated_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique(property_id,organization_id)
);

revoke all on table private.plp_direct_source_bindings from public,anon,authenticated;

insert into private.plp_direct_source_bindings(property_id,organization_id,active)
select p.id,p.organization_id,false
from public.enterprise_properties p
where p.organization_id='076a9306-5c4e-4d9d-98d3-e3a6fea968fb'::uuid
  and p.slug='plp-boracay'
on conflict(property_id) do nothing;

do $rename$
begin
  if to_regprocedure('public.plp_resort_command_center_legacy_20261001()') is null then
    alter function public.plp_resort_command_center_v1()
      rename to plp_resort_command_center_legacy_20261001;
  end if;
  if to_regprocedure('public.plp_enterprise_mobile_bootstrap_legacy_20261001()') is null then
    alter function public.plp_enterprise_mobile_bootstrap_v1()
      rename to plp_enterprise_mobile_bootstrap_legacy_20261001;
  end if;
end
$rename$;

revoke all on function public.plp_resort_command_center_legacy_20261001()
  from public,anon,authenticated;
revoke all on function public.plp_enterprise_mobile_bootstrap_legacy_20261001()
  from public,anon,authenticated;

create or replace function public.plp_resort_command_center_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid:=auth.uid();
  prop public.enterprise_properties%rowtype;
  direct_active boolean:=false;
  d date;
  total integer:=0;
  occupied integer:=0;
  arriving integer:=0;
  departing integer:=0;
  open_work integer:=0;
  priority_work integer:=0;
  reservations integer:=0;
  stays integer:=0;
  housekeeping integer:=0;
  guests integer:=0;
  folios integer:=0;
  outstanding numeric:=0;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships m
    on m.organization_id=p.organization_id
   and m.user_id=uid
   and m.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select exists(
    select 1
    from private.plp_direct_source_bindings b
    where b.property_id=prop.id
      and b.organization_id=prop.organization_id
      and b.active=true
  ) into direct_active;

  if not direct_active then
    return public.plp_resort_command_center_legacy_20261001();
  end if;

  d:=(clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select
    count(*)::integer,
    count(*) filter(where lower(coalesce(room_state,''))='occupied')::integer
  into total,occupied
  from public.enterprise_hospitality_rooms
  where organization_id=prop.organization_id;

  select
    count(*) filter(where arrival_date=d and reservation_state in('held','confirmed'))::integer,
    count(*) filter(where departure_date=d and reservation_state in('confirmed','completed'))::integer,
    count(*)::integer
  into arriving,departing,reservations
  from public.enterprise_hospitality_reservations
  where organization_id=prop.organization_id;

  select count(*)::integer into stays
  from public.enterprise_hospitality_stays
  where organization_id=prop.organization_id;

  select count(*)::integer into housekeeping
  from public.enterprise_hospitality_housekeeping_jobs
  where organization_id=prop.organization_id;

  select count(*)::integer into guests
  from public.enterprise_hospitality_guest_profiles
  where organization_id=prop.organization_id;

  select
    count(*)::integer,
    coalesce(sum(balance_amount) filter(where folio_state='open'),0)
  into folios,outstanding
  from public.enterprise_hospitality_folios
  where organization_id=prop.organization_id;

  select
    count(*)::integer,
    count(*) filter(where task_state in('blocked','in_progress'))::integer
  into open_work,priority_work
  from public.enterprise_tasks
  where organization_id=prop.organization_id
    and task_state not in('completed','cancelled');

  return jsonb_build_object(
    'schemaVersion','plp.resort.command-center.direct.v1',
    'generatedAt',clock_timestamp(),
    'businessDate',d,
    'rooms','[]'::jsonb,
    'stays','[]'::jsonb,
    'experienceSignals','[]'::jsonb,
    'roomPulse',jsonb_build_object(
      'total',total,
      'occupied',occupied,
      'available',greatest(total-occupied,0),
      'arriving',arriving,
      'departing',departing
    ),
    'operations',jsonb_build_object(
      'openWork',open_work,
      'priorityWork',priority_work,
      'channelExceptions',0
    ),
    'finance',jsonb_build_object(
      'bookedValue30dPhp',null,
      'outstandingBalancePhp',outstanding,
      'paidValue30dPhp',null
    ),
    'universalHospitality',jsonb_build_object(
      'rooms',total,
      'reservations',reservations,
      'stays',stays,
      'housekeepingJobs',housekeeping,
      'guestProfiles',guests,
      'folios',folios
    ),
    'truth',jsonb_build_object(
      'projectionOnly',true,
      'contactDetailsExcluded',true,
      'liveOperationalDataAvailable',true,
      'source','Pandora Direct / tenant-scoped Universal Hospitality',
      'externalPmsOtaConnected',false
    )
  );
end;
$$;

revoke all on function public.plp_resort_command_center_v1() from public,anon;
grant execute on function public.plp_resort_command_center_v1() to authenticated;

create or replace function public.plp_enterprise_mobile_bootstrap_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  legacy jsonb;
  command jsonb;
  org_id uuid;
  prop_id uuid;
  direct_active boolean:=false;
  d date;
  total numeric:=0;
  occupied numeric:=0;
  today jsonb;
begin
  legacy:=public.plp_enterprise_mobile_bootstrap_legacy_20261001();
  org_id:=nullif(legacy#>>'{organization,id}','')::uuid;
  prop_id:=nullif(legacy#>>'{organization,propertyId}','')::uuid;

  select exists(
    select 1
    from private.plp_direct_source_bindings b
    where b.property_id=prop_id
      and b.organization_id=org_id
      and b.active=true
  ) into direct_active;

  if not direct_active then
    return legacy;
  end if;

  command:=public.plp_resort_command_center_v1();
  d:=nullif(command->>'businessDate','')::date;
  total:=coalesce((command#>>'{roomPulse,total}')::numeric,0);
  occupied:=coalesce((command#>>'{roomPulse,occupied}')::numeric,0);

  today:=jsonb_build_object(
    'generated_at',clock_timestamp(),
    'business_date',d,
    'rooms_total',total,
    'occupied_rooms',occupied,
    'rooms_available',greatest(total-occupied,0),
    'occupancy_percent',case when total>0 then round((occupied/total)*100,1) else 0 end,
    'arrivals_today',coalesce((command#>>'{roomPulse,arriving}')::integer,0),
    'departures_today',coalesce((command#>>'{roomPulse,departing}')::integer,0),
    'sales_today_php',0,
    'open_staff_tasks',coalesce((command#>>'{operations,openWork}')::integer,0),
    'open_ota_conflicts',0,
    'source','pandora_direct'
  );

  return legacy || jsonb_build_object(
    'today',today,
    'sourceHealth',jsonb_build_object(
      'state','healthy',
      'rawState','healthy',
      'observedAt',clock_timestamp(),
      'ageHours',0,
      'message','Pandora Direct is the active PLP operational source of record. External PMS/OTA is not connected; only authenticated PLP records stored in Pandora are authoritative.',
      'environment','customer',
      'sourceProvider','pandora_direct',
      'containsMockData',false,
      'testDataQuarantined',true,
      'customerTenantActive',true,
      'customerTenantConnected',true,
      'liveBusinessSourceConnected',true,
      'liveOperationalDataAvailable',true,
      'externalPmsOtaConnected',false
    ),
    'latestHospitalitySnapshot',null,
    'guestExperience',jsonb_build_object(
      'businessDate',d,
      'snapshotBusinessDate',d,
      'inHouse','[]'::jsonb,
      'arrivals','[]'::jsonb,
      'departing','[]'::jsonb,
      'attention','[]'::jsonb,
      'containsMockData',false
    ),
    'teamAccess',coalesce(legacy->'teamAccess','{}'::jsonb)
      || jsonb_build_object('recentActivity','[]'::jsonb),
    'localAiContext',jsonb_build_object(
      'scope','plp-boracay-pandora-direct',
      'authoritativeAsOf',clock_timestamp(),
      'payload',today
    )
  );
end;
$$;

revoke all on function public.plp_enterprise_mobile_bootstrap_v1() from public,anon;
grant execute on function public.plp_enterprise_mobile_bootstrap_v1() to authenticated;

create or replace function private.plp_activate_direct_source_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  prop public.enterprise_properties%rowtype;
begin
  select * into prop
  from public.enterprise_properties
  where organization_id='076a9306-5c4e-4d9d-98d3-e3a6fea968fb'::uuid
    and slug='plp-boracay'
  order by updated_at desc,id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP customer property is missing';
  end if;

  update private.plp_direct_source_bindings
  set active=true,
      activated_at=coalesce(activated_at,clock_timestamp())
  where property_id=prop.id
    and organization_id=prop.organization_id;

  if not found then
    raise exception 'PLP Direct binding is missing';
  end if;

  update public.enterprise_properties
  set source_status='healthy',
      source_observed_at=clock_timestamp(),
      source_message='Pandora Direct is the active PLP operational source of record. External PMS/OTA is not connected; only authenticated PLP records stored in Pandora are authoritative.',
      updated_at=clock_timestamp()
  where id=prop.id;

  return jsonb_build_object(
    'ok',true,
    'propertyId',prop.id,
    'organizationId',prop.organization_id,
    'sourceProvider','pandora_direct',
    'sourceStatus','healthy',
    'externalPmsOtaConnected',false
  );
end;
$$;

revoke all on function private.plp_activate_direct_source_v1()
  from public,anon,authenticated;
