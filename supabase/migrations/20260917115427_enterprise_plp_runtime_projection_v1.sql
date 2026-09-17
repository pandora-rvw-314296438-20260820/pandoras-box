create or replace function public.enterprise_refresh_plp_runtime_overview_v1()
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','public','plp_runtime'
as $$
declare
  v_property public.enterprise_properties%rowtype;
  v_business_date date := (now() at time zone 'Asia/Manila')::date;
  v_units_total integer := 0;
  v_booking_total integer := 0;
  v_payment_total integer := 0;
  v_task_total integer := 0;
  v_conflict_total integer := 0;
  v_occupied integer := 0;
  v_available integer;
  v_arrivals integer := 0;
  v_departures integer := 0;
  v_revenue numeric(14,2);
  v_occupancy numeric(5,2);
  v_open_tasks integer := 0;
  v_done_tasks integer := 0;
  v_open_conflicts integer := 0;
  v_paid_count integer := 0;
  v_meaningful boolean := false;
begin
  select * into v_property from public.enterprise_properties
  where slug='plp-boracay' order by updated_at desc limit 1;

  if v_property.id is null then
    return jsonb_build_object('ok',false,'state','property_missing');
  end if;

  select count(*) filter (where is_active), count(*)
    into v_units_total, v_task_total
  from plp_runtime.plp_accommodations;
  v_task_total := 0;
  select count(*) into v_booking_total from plp_runtime.plp_bookings;
  select count(*) into v_payment_total from plp_runtime.plp_payments;
  select count(*) into v_task_total from plp_runtime.plp_staff_tasks;
  select count(*) into v_conflict_total from plp_runtime.plp_ota_conflicts;

  v_meaningful := v_units_total > 0 or v_booking_total > 0
    or v_payment_total > 0 or v_task_total > 0 or v_conflict_total > 0;

  if not v_meaningful then
    update public.enterprise_properties
    set source_status='connecting', source_observed_at=null,
        source_message='PLP backend is connected. Waiting for accommodation and operating records before showing live metrics.',
        updated_at=now()
    where id=v_property.id;

    update public.enterprise_source_connections
    set status=case when source_type in ('reservations','payments','housekeeping')
          then 'connecting' else 'not_connected' end,
        customer_message=case source_type
          when 'reservations' then 'PLP booking storage is connected; waiting for accommodation and reservation records.'
          when 'payments' then 'PLP payment storage is connected; waiting for the first verified payment record.'
          when 'housekeeping' then 'PLP staff operations are connected; room-readiness data is not available yet.'
          else customer_message end,
        updated_at=now()
    where property_id=v_property.id;

    return jsonb_build_object(
      'ok',true,'state','waiting_for_business_data','snapshotWritten',false
    );
  end if;

  select count(distinct accommodation_id) into v_occupied
  from plp_runtime.plp_bookings
  where accommodation_id is not null
    and check_in <= v_business_date and check_out > v_business_date
    and upper(status) not in ('CANCELLED','FAILED','EXPIRED','REFUNDED');

  select count(*) into v_arrivals from plp_runtime.plp_bookings
  where check_in=v_business_date
    and upper(status) not in ('CANCELLED','FAILED','EXPIRED','REFUNDED');

  select count(*) into v_departures from plp_runtime.plp_bookings
  where check_out=v_business_date
    and upper(status) not in ('CANCELLED','FAILED','EXPIRED','REFUNDED');

  if v_units_total > 0 then
    v_available := greatest(v_units_total-v_occupied,0);
    v_occupancy := round((v_occupied::numeric*100.0)/v_units_total,2);
  end if;

  if v_payment_total > 0 then
    select coalesce(sum(amount_php),0), count(*) into v_revenue, v_paid_count
    from plp_runtime.plp_payments
    where upper(status) in ('PAID','COMPLETED','SUCCEEDED','CAPTURED')
      and (coalesce(paid_at,created_at) at time zone 'Asia/Manila')::date=v_business_date;
  end if;

  select count(*) into v_open_tasks from plp_runtime.plp_staff_tasks
  where status in ('open','in_progress');
  select count(*) into v_done_tasks from plp_runtime.plp_staff_tasks
  where status='done'
    and (coalesce(completed_at,updated_at) at time zone 'Asia/Manila')::date=v_business_date;
  select count(*) into v_open_conflicts from plp_runtime.plp_ota_conflicts
  where status='open';

  insert into public.enterprise_hospitality_snapshots(
    organization_id,property_id,business_date,as_of,occupancy_percent,
    rooms_total,rooms_available,arrivals_today,departures_today,revenue_today,
    adr,revpar,rooms_ready,rooms_not_ready,data_quality_state,source_label
  ) values (
    v_property.organization_id,v_property.id,v_business_date,now(),v_occupancy,
    v_units_total,v_available,v_arrivals,v_departures,v_revenue,
    null,null,null,null,'partial','PLP runtime'
  );

  update public.enterprise_properties
  set source_status=case when v_units_total>0 then 'healthy' else 'connecting' end,
      source_observed_at=now(),
      source_message=case when v_units_total>0
        then 'Live PLP reservations and operating aggregates are connected. Some feeds may still be incomplete.'
        else 'PLP operating records are arriving, but accommodation inventory is not configured yet.' end,
      updated_at=now()
  where id=v_property.id;

  update public.enterprise_source_connections
  set status=case source_type
        when 'reservations' then case when v_units_total>0 then 'healthy' else 'connecting' end
        when 'payments' then case when v_payment_total>0 then 'healthy' else 'connecting' end
        when 'housekeeping' then 'connecting'
        else 'not_connected' end,
      last_success_at=case
        when source_type='reservations' and v_units_total>0 then now()
        when source_type='payments' and v_payment_total>0 then now()
        else last_success_at end,
      last_attempt_at=case
        when source_type in ('reservations','payments','housekeeping') then now()
        else last_attempt_at end,
      customer_message=case source_type
        when 'reservations' then case when v_units_total>0
          then 'Live reservation and availability aggregates are connected.'
          else 'Waiting for accommodation inventory before occupancy can be verified.' end
        when 'payments' then case when v_payment_total>0
          then 'Live payment aggregates are connected.'
          else 'Payment storage is connected; waiting for the first verified payment record.' end
        when 'housekeeping' then 'Staff operations are connected; dedicated room-readiness data is still pending.'
        else customer_message end,
      updated_at=now()
  where property_id=v_property.id;

  if v_open_tasks>0 then
    insert into public.enterprise_attention_items(
      organization_id,property_id,source_key,priority,category,title,summary,
      status,occurred_at,updated_at
    ) values (
      v_property.organization_id,v_property.id,'plp:open_staff_tasks',
      case when v_open_tasks>=5 then 'high' else 'medium' end,'operations',
      v_open_tasks||' staff '||case when v_open_tasks=1 then 'task needs' else 'tasks need' end||' attention',
      'Review open PLP staff tasks in operations.','open',now(),now()
    ) on conflict(property_id,source_key) do update set
      priority=excluded.priority,title=excluded.title,summary=excluded.summary,
      status='open',resolved_at=null,occurred_at=excluded.occurred_at,updated_at=now();
  else
    update public.enterprise_attention_items
    set status='resolved',resolved_at=now(),updated_at=now()
    where property_id=v_property.id and source_key='plp:open_staff_tasks'
      and status in ('open','acknowledged');
  end if;

  if v_open_conflicts>0 then
    insert into public.enterprise_attention_items(
      organization_id,property_id,source_key,priority,category,title,summary,
      status,occurred_at,updated_at
    ) values (
      v_property.organization_id,v_property.id,'plp:open_ota_conflicts','high','reservations',
      v_open_conflicts||' booking-channel '||case when v_open_conflicts=1 then 'conflict needs' else 'conflicts need' end||' review',
      'Review unresolved OTA booking conflicts.','open',now(),now()
    ) on conflict(property_id,source_key) do update set
      title=excluded.title,summary=excluded.summary,status='open',resolved_at=null,
      occurred_at=excluded.occurred_at,updated_at=now();
  else
    update public.enterprise_attention_items
    set status='resolved',resolved_at=now(),updated_at=now()
    where property_id=v_property.id and source_key='plp:open_ota_conflicts'
      and status in ('open','acknowledged');
  end if;

  if v_done_tasks>0 then
    insert into public.enterprise_business_activity(
      organization_id,property_id,activity_key,category,title,summary,occurred_at,source_label
    ) values (
      v_property.organization_id,v_property.id,'plp:tasks_done:'||v_business_date,'operations',
      v_done_tasks||' staff '||case when v_done_tasks=1 then 'task completed' else 'tasks completed' end||' today',
      'PLP staff operations completed today.',now(),'PLP runtime'
    ) on conflict(property_id,activity_key) do update set
      title=excluded.title,summary=excluded.summary,occurred_at=excluded.occurred_at;
  end if;

  if v_payment_total>0 and v_paid_count>0 then
    insert into public.enterprise_business_activity(
      organization_id,property_id,activity_key,category,title,summary,occurred_at,source_label
    ) values (
      v_property.organization_id,v_property.id,'plp:payments:'||v_business_date,'payments',
      v_paid_count||' verified '||case when v_paid_count=1 then 'payment' else 'payments' end||' today',
      'Verified payment activity is reflected in today’s sales total.',now(),'PLP runtime'
    ) on conflict(property_id,activity_key) do update set
      title=excluded.title,summary=excluded.summary,occurred_at=excluded.occurred_at;
  end if;

  return jsonb_build_object(
    'ok',true,
    'state',case when v_units_total>0 then 'healthy' else 'connecting' end,
    'snapshotWritten',true,
    'businessDate',v_business_date,
    'unitsTotal',v_units_total,
    'bookingCount',v_booking_total,
    'paymentCount',v_payment_total,
    'openTasks',v_open_tasks,
    'openConflicts',v_open_conflicts
  );
end;
$$;

revoke all on function public.enterprise_refresh_plp_runtime_overview_v1()
  from public,anon,authenticated;
grant execute on function public.enterprise_refresh_plp_runtime_overview_v1()
  to service_role;

create or replace function private.enterprise_refresh_plp_runtime_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
begin
  perform public.enterprise_refresh_plp_runtime_overview_v1();
  return null;
end;
$$;
revoke all on function private.enterprise_refresh_plp_runtime_trigger_v1()
  from public,anon,authenticated;

create or replace function private.enterprise_install_plp_projection_trigger_v1(
  p_table regclass,
  p_name text
) returns void
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
begin
  execute format('drop trigger if exists %I on %s',p_name,p_table);
  execute format(
    'create trigger %I after insert or update or delete on %s for each statement execute function private.enterprise_refresh_plp_runtime_trigger_v1()',
    p_name,p_table
  );
end;
$$;

select private.enterprise_install_plp_projection_trigger_v1(
  'plp_runtime.plp_accommodations'::regclass,'enterprise_plp_accommodations_refresh');
select private.enterprise_install_plp_projection_trigger_v1(
  'plp_runtime.plp_bookings'::regclass,'enterprise_plp_bookings_refresh');
select private.enterprise_install_plp_projection_trigger_v1(
  'plp_runtime.plp_payments'::regclass,'enterprise_plp_payments_refresh');
select private.enterprise_install_plp_projection_trigger_v1(
  'plp_runtime.plp_staff_tasks'::regclass,'enterprise_plp_staff_tasks_refresh');
select private.enterprise_install_plp_projection_trigger_v1(
  'plp_runtime.plp_ota_conflicts'::regclass,'enterprise_plp_ota_conflicts_refresh');

drop function private.enterprise_install_plp_projection_trigger_v1(regclass,text);

select public.enterprise_refresh_plp_runtime_overview_v1();

comment on function public.enterprise_refresh_plp_runtime_overview_v1() is
  'Projects PLP runtime data into customer-safe Enterprise aggregates only; no guest PII or engineering telemetry is copied.';
