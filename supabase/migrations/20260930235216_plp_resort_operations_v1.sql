create or replace function public.plp_resort_operations_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  work_items jsonb := '[]'::jsonb;
  channel_conflicts jsonb := '[]'::jsonb;
  housekeeping_jobs jsonb := '[]'::jsonb;
  folios jsonb := '[]'::jsonb;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'PLP Boracay property is not configured' using errcode='55000';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id=prop.organization_id
      and m.user_id=uid
      and m.status::text='active'
  ) then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into work_items
  from (
    select
      t.updated_at,
      jsonb_build_object(
        'id',t.id,
        'bookingReference',t.booking_reference,
        'kind',t.kind,
        'category',t.category,
        'priority',t.priority,
        'status',t.status,
        'title',t.title,
        'note',t.note,
        'source',t.source,
        'actor',t.actor,
        'createdAt',t.created_at,
        'updatedAt',t.updated_at,
        'completedAt',t.completed_at,
        'isTestData',
          lower(coalesce(t.source,'')) like 'qa_%'
          or lower(coalesce(t.actor,'')) like '%qa%'
          or lower(coalesce(t.note,'')) like '%mock%'
      ) as payload
    from plp_runtime.plp_staff_tasks t
    order by t.updated_at desc
    limit 80
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into channel_conflicts
  from (
    select
      c.updated_at,
      jsonb_build_object(
        'id',c.id,
        'channelKey',c.channel_key,
        'conflictType',c.conflict_type,
        'internalBookingReference',c.internal_booking_reference,
        'otaReservationReference',c.ota_reservation_reference,
        'accommodationName',c.accommodation_name,
        'startDate',c.start_date,
        'endDate',c.end_date,
        'severity',c.severity,
        'status',c.status,
        'resolutionNote',c.resolution_note,
        'resolutionStatus',c.resolution_status,
        'resolutionType',c.resolution_type,
        'createdAt',c.created_at,
        'updatedAt',c.updated_at,
        'isTestData',
          lower(coalesce(c.internal_booking_reference,'')) like 'mock-%'
          or lower(coalesce(c.ota_reservation_reference,'')) like 'mock-%'
      ) as payload
    from plp_runtime.plp_ota_conflicts c
    order by c.updated_at desc
    limit 50
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.created_at desc),'[]'::jsonb)
  into housekeeping_jobs
  from (
    select
      h.created_at,
      jsonb_build_object(
        'taskEntityId',h.task_entity_id,
        'roomLocationEntityId',h.room_location_entity_id,
        'housekeepingType',h.housekeeping_type,
        'createdAt',h.created_at
      ) as payload
    from public.enterprise_hospitality_housekeeping_jobs h
    where h.organization_id=prop.organization_id
    order by h.created_at desc
    limit 50
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.updated_at desc),'[]'::jsonb)
  into folios
  from (
    select
      f.updated_at,
      jsonb_build_object(
        'entityId',f.entity_id,
        'stayEntityId',f.stay_entity_id,
        'currency',f.currency,
        'folioState',f.folio_state,
        'balanceAmount',f.balance_amount,
        'createdAt',f.created_at,
        'updatedAt',f.updated_at
      ) as payload
    from public.enterprise_hospitality_folios f
    where f.organization_id=prop.organization_id
    order by f.updated_at desc
    limit 50
  ) q;

  return jsonb_build_object(
    'schemaVersion','plp.resort.operations.v1',
    'generatedAt',clock_timestamp(),
    'workItems',work_items,
    'channelConflicts',channel_conflicts,
    'housekeepingJobs',housekeeping_jobs,
    'folios',folios,
    'truth',jsonb_build_object(
      'source','existing PLP runtime + Universal hospitality records',
      'projectionOnly',true,
      'noSyntheticRows',true
    )
  );
end;
$$;

revoke execute on function public.plp_resort_operations_v1()
  from public,anon;
grant execute on function public.plp_resort_operations_v1()
  to authenticated;

