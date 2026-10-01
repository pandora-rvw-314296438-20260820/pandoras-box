create or replace function public.plp_resort_command_center_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  business_date date;
  rooms jsonb := '[]'::jsonb;
  stays jsonb := '[]'::jsonb;
  experience_signals jsonb := '[]'::jsonb;
  rooms_total integer := 0;
  rooms_occupied integer := 0;
  rooms_arriving integer := 0;
  rooms_departing integer := 0;
  open_tasks integer := 0;
  priority_tasks integer := 0;
  open_conflicts integer := 0;
  booked_value_30d numeric := 0;
  outstanding_balance numeric := 0;
  paid_value_30d numeric := 0;
  universal_rooms integer := 0;
  universal_reservations integer := 0;
  universal_stays integer := 0;
  universal_housekeeping integer := 0;
  universal_guest_profiles integer := 0;
  universal_folios integer := 0;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select * into prop
  from public.enterprise_properties p
  where p.slug='plp-boracay'
  order by p.updated_at desc, p.id desc
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

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select count(*)::integer into rooms_total
  from plp_runtime.plp_accommodations a
  where a.is_active=true;

  select count(*)::integer into rooms_occupied
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in <= business_date
        and b.check_out > business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
    );

  select count(*)::integer into rooms_arriving
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in=business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
    );

  select count(*)::integer into rooms_departing
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1 from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_out=business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
    );

  select coalesce(jsonb_agg(q.payload order by q.name),'[]'::jsonb)
  into rooms
  from (
    select a.name,
      jsonb_build_object(
        'id',a.id,
        'name',a.name,
        'capacity',a.capacity,
        'bedrooms',a.bedrooms,
        'nightlyRatePhp',a.nightly_rate_php,
        'state',
          case
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_out=business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
            ) then 'departure'
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in=business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
            ) then 'arrival'
            when exists (
              select 1 from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in <= business_date
                and b.check_out > business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
            ) then 'occupied'
            else 'available'
          end
      ) as payload
    from plp_runtime.plp_accommodations a
    where a.is_active=true
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.check_in, q.full_name),'[]'::jsonb)
  into stays
  from (
    select b.check_in, g.full_name,
      jsonb_build_object(
        'id',b.id,
        'bookingReference',b.booking_reference,
        'guestId',g.id,
        'fullName',g.full_name,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'guestCount',b.guest_count,
        'nights',b.nights,
        'status',b.status,
        'paymentStatus',b.payment_status,
        'totalAmountPhp',b.total_amount_php,
        'balanceAmountPhp',b.balance_amount_php,
        'hasSpecialRequest',nullif(trim(coalesce(b.special_requests,'')),'') is not null,
        'specialRequest',nullif(trim(coalesce(b.special_requests,'')),'')
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out >= business_date
      and b.check_in <= business_date + 30
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
    order by b.check_in, g.full_name
    limit 24
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.check_in, q.full_name),'[]'::jsonb)
  into experience_signals
  from (
    select b.check_in, g.full_name,
      jsonb_build_object(
        'bookingReference',b.booking_reference,
        'fullName',g.full_name,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'request',nullif(trim(coalesce(b.special_requests,'')),'')
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out >= business_date
      and b.check_in <= business_date + 30
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
      and nullif(trim(coalesce(b.special_requests,'')),'') is not null
    order by b.check_in, g.full_name
    limit 12
  ) q;

  select count(*)::integer,
         count(*) filter (where lower(coalesce(t.priority,'')) in ('critical','high'))::integer
  into open_tasks, priority_tasks
  from plp_runtime.plp_staff_tasks t
  where lower(coalesce(t.status,'')) not in
    ('done','completed','complete','cancelled','canceled','closed');

  select count(*)::integer into open_conflicts
  from plp_runtime.plp_ota_conflicts c
  where lower(coalesce(c.status,'')) not in ('resolved','closed','cancelled','canceled')
    and lower(coalesce(c.resolution_status,'')) not in ('resolved','closed');

  select coalesce(sum(b.total_amount_php),0),coalesce(sum(b.balance_amount_php),0)
  into booked_value_30d,outstanding_balance
  from plp_runtime.plp_bookings b
  where b.check_in between business_date and business_date + 30
    and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED');

  select coalesce(sum(p.amount_php),0) into paid_value_30d
  from plp_runtime.plp_payments p
  where lower(coalesce(p.status,'')) in ('paid','succeeded','complete','completed')
    and p.paid_at >= business_date::timestamp
    and p.paid_at < (business_date + 30)::timestamp;

  select count(*)::integer into universal_rooms from public.enterprise_hospitality_rooms r where r.organization_id=prop.organization_id;
  select count(*)::integer into universal_reservations from public.enterprise_hospitality_reservations r where r.organization_id=prop.organization_id;
  select count(*)::integer into universal_stays from public.enterprise_hospitality_stays s where s.organization_id=prop.organization_id;
  select count(*)::integer into universal_housekeeping from public.enterprise_hospitality_housekeeping_jobs h where h.organization_id=prop.organization_id;
  select count(*)::integer into universal_guest_profiles from public.enterprise_hospitality_guest_profiles g where g.organization_id=prop.organization_id;
  select count(*)::integer into universal_folios from public.enterprise_hospitality_folios f where f.organization_id=prop.organization_id;

  return jsonb_build_object(
    'schemaVersion','plp.resort.command-center.v1',
    'generatedAt',clock_timestamp(),
    'businessDate',business_date,
    'rooms',rooms,
    'stays',stays,
    'experienceSignals',experience_signals,
    'roomPulse',jsonb_build_object(
      'total',rooms_total,
      'occupied',rooms_occupied,
      'available',greatest(rooms_total-rooms_occupied,0),
      'arriving',rooms_arriving,
      'departing',rooms_departing
    ),
    'operations',jsonb_build_object(
      'openWork',open_tasks,
      'priorityWork',priority_tasks,
      'channelExceptions',open_conflicts
    ),
    'finance',jsonb_build_object(
      'bookedValue30dPhp',booked_value_30d,
      'outstandingBalancePhp',outstanding_balance,
      'paidValue30dPhp',paid_value_30d
    ),
    'universalHospitality',jsonb_build_object(
      'rooms',universal_rooms,
      'reservations',universal_reservations,
      'stays',universal_stays,
      'housekeepingJobs',universal_housekeeping,
      'guestProfiles',universal_guest_profiles,
      'folios',universal_folios
    ),
    'truth',jsonb_build_object(
      'projectionOnly',true,
      'contactDetailsExcluded',true,
      'source','existing PLP runtime + Universal hospitality records'
    )
  );
end;
$$;

revoke execute on function public.plp_resort_command_center_v1() from public, anon;
grant execute on function public.plp_resort_command_center_v1() to authenticated;

