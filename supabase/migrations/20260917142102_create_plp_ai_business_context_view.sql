-- Source reconstruction of provider view 20260917142102.

create or replace view plp_runtime.plp_ai_business_context as
with cfg as (
  select (now() at time zone 'Asia/Manila')::date as business_date
),
rooms as (
  select count(*) filter (where a.is_active)::integer as rooms_total
  from plp_runtime.plp_accommodations a
),
active_bookings as (
  select b.*
  from plp_runtime.plp_bookings b
  where upper(b.status) not in ('CANCELLED','FAILED','EXPIRED','REFUNDED')
),
metrics as (
  select
    count(distinct b.accommodation_id)
      filter (where b.accommodation_id is not null
              and b.check_in <= c.business_date
              and b.check_out > c.business_date)::integer as occupied_rooms,
    count(*) filter (where b.check_in=c.business_date)::integer as arrivals_today,
    count(*) filter (where b.check_out=c.business_date)::integer as departures_today,
    count(*) filter (
      where upper(coalesce(b.payment_status,'')) not in ('PAID','COMPLETED','SUCCEEDED','CAPTURED')
        and b.check_out >= c.business_date
    )::integer as unpaid_active_bookings
  from active_bookings b cross join cfg c
),
payments as (
  select coalesce(sum(p.amount_php) filter (
    where upper(p.status) in ('PAID','COMPLETED','SUCCEEDED','CAPTURED')
      and (coalesce(p.paid_at,p.created_at) at time zone 'Asia/Manila')::date=c.business_date
  ),0)::numeric(14,2) as sales_today_php
  from plp_runtime.plp_payments p cross join cfg c
),
ops as (
  select
    (select count(*)::integer from plp_runtime.plp_staff_tasks
      where status in ('open','in_progress')) as open_staff_tasks,
    (select count(*)::integer from plp_runtime.plp_ota_conflicts
      where status='open') as open_ota_conflicts
),
arrivals as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'bookingReference',b.booking_reference,
    'guestName',g.full_name,
    'accommodation',b.accommodation_name,
    'checkIn',b.check_in,
    'checkOut',b.check_out,
    'guestCount',b.guest_count,
    'status',b.status,
    'paymentStatus',b.payment_status
  ) order by b.check_in,b.booking_reference),'[]'::jsonb) as upcoming_arrivals
  from active_bookings b
  join plp_runtime.plp_guests g on g.id=b.guest_id
  cross join cfg c
  where b.check_in >= c.business_date and b.check_in < c.business_date + 7
),
departures as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'bookingReference',b.booking_reference,
    'guestName',g.full_name,
    'accommodation',b.accommodation_name,
    'checkOut',b.check_out,
    'status',b.status
  ) order by b.check_out,b.booking_reference),'[]'::jsonb) as upcoming_departures
  from active_bookings b
  join plp_runtime.plp_guests g on g.id=b.guest_id
  cross join cfg c
  where b.check_out >= c.business_date and b.check_out < c.business_date + 7
)
select
  c.business_date,
  r.rooms_total,
  m.occupied_rooms,
  greatest(r.rooms_total-m.occupied_rooms,0) as rooms_available,
  case when r.rooms_total>0
    then round(m.occupied_rooms::numeric*100.0/r.rooms_total::numeric,2)
    else null::numeric end as occupancy_percent,
  m.arrivals_today,
  m.departures_today,
  p.sales_today_php,
  m.unpaid_active_bookings,
  o.open_staff_tasks,
  o.open_ota_conflicts,
  a.upcoming_arrivals,
  d.upcoming_departures,
  clock_timestamp() as generated_at
from cfg c
cross join rooms r
cross join metrics m
cross join payments p
cross join ops o
cross join arrivals a
cross join departures d;

revoke all on table plp_runtime.plp_ai_business_context from public, anon, authenticated;
grant select on table plp_runtime.plp_ai_business_context to service_role;
