-- Fail closed when the PLP customer tenant exists but no current verified
-- PMS/OTA/business-source observation exists. Tenant activation and source
-- connectivity are distinct facts; do not turn absence of live source data
-- into verified zero occupancy, zero revenue, or room availability.
create or replace function public.plp_enterprise_mobile_bootstrap_v1()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  prop public.enterprise_properties%rowtype;
  member public.memberships%rowtype;
  profile public.profiles%rowtype;
  ctx jsonb;
  snap jsonb;
  business_date date;
  in_house jsonb := '[]'::jsonb;
  arrivals jsonb := '[]'::jsonb;
  departing jsonb := '[]'::jsonb;
  attention jsonb := '[]'::jsonb;
  team_members jsonb := '[]'::jsonb;
  team_activity jsonb := '[]'::jsonb;
  active_member_count integer := 0;
  total_member_count integer := 0;
  staff_identity_count integer := 0;
  has_mock boolean := false;
  allow_test_data boolean := false;
  source_age_hours numeric;
  effective_source_state text;
  effective_source_message text;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships resolver
    on resolver.organization_id=p.organization_id
   and resolver.user_id=uid
   and resolver.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  allow_test_data := prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;

  select * into member
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.user_id=uid
    and m.status::text='active'
  limit 1;

  if member.user_id is null then
    raise exception 'active PLP membership required' using errcode='42501';
  end if;

  select * into profile
  from public.profiles p
  where p.id=uid;

  if allow_test_data then
    select to_jsonb(c) into ctx
    from plp_runtime.plp_ai_business_context c
    limit 1;
  else
    ctx := '{}'::jsonb;
  end if;

  select to_jsonb(s) into snap
  from public.enterprise_hospitality_snapshots s
  where s.organization_id=prop.organization_id
    and s.property_id=prop.id
  order by s.as_of desc, s.created_at desc, s.id desc
  limit 1;

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select coalesce(jsonb_agg(q.payload order by q.check_in, q.full_name),'[]'::jsonb)
  into in_house
  from (
    select
      b.check_in,
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',greatest(1,(business_date-b.check_in)+1),
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','In-house',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out > business_date
      and (
        b.check_in < business_date
        or upper(coalesce(b.status,'')) in ('CHECKED_IN','IN_HOUSE')
      )
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
      and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.full_name),'[]'::jsonb)
  into arrivals
  from (
    select
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',1,
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','Arriving',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_in=business_date
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
      and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
  ) q;

  select coalesce(jsonb_agg(q.payload order by q.full_name),'[]'::jsonb)
  into departing
  from (
    select
      g.full_name,
      jsonb_build_object(
        'id',g.id,
        'fullName',g.full_name,
        'bookingReference',b.booking_reference,
        'accommodationName',b.accommodation_name,
        'checkIn',b.check_in,
        'checkOut',b.check_out,
        'stayDays',b.nights,
        'dayOfStay',b.nights,
        'guestCount',b.guest_count,
        'paymentStatus',b.payment_status,
        'status',b.status,
        'displayStatus','Departing',
        'specialRequest',b.special_requests,
        'source',b.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out=business_date
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
      and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.priority_rank, q.updated_at desc),
    '[]'::jsonb
  )
  into attention
  from (
    select
      case lower(coalesce(t.priority,''))
        when 'critical' then 0
        when 'high' then 1
        when 'medium' then 2
        else 3
      end as priority_rank,
      t.updated_at,
      jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'note',t.note,
        'priority',t.priority,
        'category',t.category,
        'status',t.status,
        'bookingReference',t.booking_reference,
        'fullName',g.full_name,
        'accommodationName',b.accommodation_name,
        'source',t.source,
        'isMock',
          lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
          or lower(coalesce(t.source,'')) like 'qa_%'
          or lower(coalesce(b.source,'')) like 'qa_%'
      ) as payload
    from plp_runtime.plp_staff_tasks t
    left join plp_runtime.plp_bookings b
      on b.booking_reference=t.booking_reference
    left join plp_runtime.plp_guests g
      on g.id=b.guest_id
    where lower(coalesce(t.status,'')) not in
      ('done','completed','complete','cancelled','canceled','closed')
      and (allow_test_data or not private.plp_task_is_test_v1(t.id))
  ) q;

  if allow_test_data then
    select exists(
      select 1
      from plp_runtime.plp_bookings b
      left join plp_runtime.plp_guests g on g.id=b.guest_id
      where private.plp_booking_is_test_v1(b.id)
    ) into has_mock;
  else
    has_mock := false;
  end if;

  source_age_hours := case
    when prop.source_observed_at is null then null
    else extract(epoch from (clock_timestamp()-prop.source_observed_at))/3600.0
  end;
  effective_source_state := case
    when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid then 'stale'
    when has_mock then 'stale'
    when prop.source_observed_at is null then 'not_connected'
    when prop.source_observed_at < clock_timestamp()-interval '6 hours' then 'stale'
    else prop.source_status
  end;
  effective_source_message := case
    when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
      then 'Demo/staging PLP data. Customer production tenant is not connected.'
    when has_mock
      then 'This workspace contains QA/mock hospitality records and is not verified as fully live.'
    when prop.source_observed_at is null
      then 'No verified source observation is available.'
    when prop.source_observed_at < clock_timestamp()-interval '6 hours'
      then 'Business source data is stale and should not be presented as current.'
    else coalesce(nullif(prop.source_message,''),'Source observation is current.')
  end;


  select count(*)::integer
  into active_member_count
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.status::text='active';

  select count(*)::integer
  into staff_identity_count
  from plp_runtime.plp_staff_identities s
  where s.active=true
    and exists (
      select 1 from public.memberships m
      where m.organization_id=prop.organization_id
        and m.user_id=s.auth_user_id
        and m.status::text='active'
    );

  with candidates as (
    select
      m.user_id,
      coalesce(nullif(trim(p.display_name),''),'PLP team member') as display_name,
      case lower(m.role::text)
        when 'owner' then 'Owner'
        when 'admin' then 'Administrator'
        else initcap(replace(m.role::text,'_',' '))
      end as role_label,
      m.role::text as access_role,
      m.status::text as access_status,
      m.status::text='active' as active,
      'membership'::text as source,
      m.updated_at,
      0 as source_rank
    from public.memberships m
    left join public.profiles p on p.id=m.user_id
    where m.organization_id=prop.organization_id
  ),
  ranked as (
    select
      c.*,
      row_number() over (
        partition by c.user_id
        order by c.source_rank, c.updated_at desc
      ) as rn
    from candidates c
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',r.user_id,
        'displayName',r.display_name,
        'roleLabel',r.role_label,
        'accessRole',r.access_role,
        'accessStatus',r.access_status,
        'active',r.active,
        'source',r.source,
        'isCurrentUser',r.user_id=uid
      )
      order by
        case lower(r.access_role)
          when 'owner' then 0
          when 'admin' then 1
          else 2
        end,
        r.display_name
    ),
    '[]'::jsonb
  )
  into team_members
  from ranked r
  where r.rn=1;

  total_member_count := jsonb_array_length(team_members);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'actor',coalesce(nullif(trim(t.actor),''),'PLP team'),
        'category',t.category,
        'status',t.status,
        'updatedAt',t.updated_at,
        'isMock',lower(coalesce(t.source,'')) like 'qa_%'
      )
      order by t.updated_at desc
    ),
    '[]'::jsonb
  )
  into team_activity
  from (
    select *
    from plp_runtime.plp_staff_tasks t
    where allow_test_data or not private.plp_task_is_test_v1(t.id)
    order by updated_at desc
    limit 12
  ) t;

  return jsonb_build_object(
    'schemaVersion','plp.enterprise.mobile-bootstrap.v6',
    'generatedAt',clock_timestamp(),
    'organization',jsonb_build_object(
      'id',prop.organization_id,
      'propertyId',prop.id,
      'propertySlug',prop.slug,
      'propertyName',prop.display_name,
      'businessIdentity','Luxury Resort',
      'timezone',prop.timezone,
      'currency',prop.currency
    ),
    'user',jsonb_build_object(
      'id',uid,
      'displayName',coalesce(nullif(trim(profile.display_name),''),'PLP administrator'),
      'role',member.role::text,
      'timezone',coalesce(profile.timezone,prop.timezone)
    ),
    'today',coalesce(ctx,'{}'::jsonb),
    'sourceHealth',jsonb_build_object(
      'state',effective_source_state,
      'rawState',prop.source_status,
      'observedAt',prop.source_observed_at,
      'ageHours',source_age_hours,
      'message',effective_source_message,
      'environment',case
        when prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid
          then 'demo_staging'
        else 'customer'
      end,
      'containsMockData',has_mock,
      'testDataQuarantined',not allow_test_data,
      'customerTenantActive',
        prop.organization_id<>'2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid,
      'customerTenantConnected',
        effective_source_state in ('healthy','current','live','ready'),
      'liveBusinessSourceConnected',
        effective_source_state in ('healthy','current','live','ready'),
      'liveOperationalDataAvailable',
        effective_source_state in ('healthy','current','live','ready')
    ),
    'latestHospitalitySnapshot',snap,
    'guestExperience',jsonb_build_object(
      'businessDate',business_date,
      'snapshotBusinessDate',snap->>'business_date',
      'inHouse',in_house,
      'arrivals',arrivals,
      'departing',departing,
      'attention',attention,
      'containsMockData',has_mock
    ),
    'teamAccess',jsonb_build_object(
      'members',team_members,
      'recentActivity',team_activity,
      'activeMemberCount',active_member_count,
      'totalMemberCount',total_member_count,
      'staffIdentityCount',staff_identity_count,
      'currentUserRole',member.role::text,
      'canManageTeam',lower(member.role::text) in ('owner','admin'),
      'accessModel','organization_membership_all_statuses'
    ),
    'localAiContext',jsonb_build_object(
      'scope','plp-boracay-authorized-snapshot',
      'authoritativeAsOf',coalesce(ctx->>'generated_at',prop.source_observed_at::text),
      'payload',coalesce(ctx,'{}'::jsonb)
    )
  );
end;
$$;

revoke all on function public.plp_enterprise_mobile_bootstrap_v1()
  from public, anon;
grant execute on function public.plp_enterprise_mobile_bootstrap_v1()
  to authenticated;

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
  allow_test_data boolean := false;
  live_operational_data_available boolean := false;
begin
  if uid is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select p.* into prop
  from public.enterprise_properties p
  join public.memberships resolver
    on resolver.organization_id=p.organization_id
   and resolver.user_id=uid
   and resolver.status::text='active'
  where p.slug='plp-boracay'
  order by p.updated_at desc,p.id desc
  limit 1;

  if prop.id is null then
    raise exception 'active PLP membership required' using errcode='42501';
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

  allow_test_data := prop.organization_id='2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;
  live_operational_data_available :=
    prop.source_observed_at is not null
    and prop.source_observed_at >= clock_timestamp()-interval '6 hours'
    and lower(coalesce(prop.source_status,'')) in ('healthy','current','live','ready');

  business_date :=
    (clock_timestamp() at time zone coalesce(nullif(prop.timezone,''),'Asia/Manila'))::date;

  select count(*)::integer
  into rooms_total
  from plp_runtime.plp_accommodations a
  where a.is_active=true;

  select count(*)::integer
  into rooms_occupied
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in <= business_date
        and b.check_out > business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
    );

  select count(*)::integer
  into rooms_arriving
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_in=business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
    );

  select count(*)::integer
  into rooms_departing
  from plp_runtime.plp_accommodations a
  where a.is_active=true
    and exists (
      select 1
      from plp_runtime.plp_bookings b
      where b.accommodation_id=a.id
        and b.check_out=business_date
        and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
    );

  select coalesce(jsonb_agg(q.payload order by q.name),'[]'::jsonb)
  into rooms
  from (
    select
      a.name,
      jsonb_build_object(
        'id',a.id,
        'name',a.name,
        'capacity',a.capacity,
        'bedrooms',a.bedrooms,
        'nightlyRatePhp',a.nightly_rate_php,
        'state',
          case
            when not live_operational_data_available then 'unknown'
            when exists (
              select 1
              from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_out=business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
            ) then 'departure'
            when exists (
              select 1
              from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in=business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
            ) then 'arrival'
            when exists (
              select 1
              from plp_runtime.plp_bookings b
              where b.accommodation_id=a.id
                and b.check_in <= business_date
                and b.check_out > business_date
                and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED','CHECKED_OUT')
        and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
            ) then 'occupied'
            else 'available'
          end
      ) as payload
    from plp_runtime.plp_accommodations a
    where a.is_active=true
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.check_in, q.full_name),
    '[]'::jsonb
  )
  into stays
  from (
    select
      b.check_in,
      g.full_name,
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
        'hasSpecialRequest',
          nullif(trim(coalesce(b.special_requests,'')),'') is not null,
        'specialRequest',
          nullif(trim(coalesce(b.special_requests,'')),'')
      ) as payload
    from plp_runtime.plp_bookings b
    join plp_runtime.plp_guests g on g.id=b.guest_id
    where b.check_out >= business_date
      and b.check_in <= business_date + 30
      and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
      and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
    order by b.check_in, g.full_name
    limit 24
  ) q;

  select coalesce(
    jsonb_agg(q.payload order by q.check_in, q.full_name),
    '[]'::jsonb
  )
  into experience_signals
  from (
    select
      b.check_in,
      g.full_name,
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
      and (allow_test_data or not private.plp_booking_is_test_v1(b.id))
      and nullif(trim(coalesce(b.special_requests,'')),'') is not null
    order by b.check_in, g.full_name
    limit 12
  ) q;

  select
    count(*)::integer,
    count(*) filter (
      where lower(coalesce(t.priority,'')) in ('critical','high')
    )::integer
  into open_tasks, priority_tasks
  from plp_runtime.plp_staff_tasks t
  where lower(coalesce(t.status,'')) not in
    ('done','completed','complete','cancelled','canceled','closed')
    and (allow_test_data or not private.plp_task_is_test_v1(t.id));

  select count(*)::integer
  into open_conflicts
  from plp_runtime.plp_ota_conflicts c
  where lower(coalesce(c.status,'')) not in
      ('resolved','closed','cancelled','canceled')
    and lower(coalesce(c.resolution_status,'')) not in
      ('resolved','closed')
    and (allow_test_data or not private.plp_conflict_is_test_v1(c.id));

  select
    coalesce(sum(b.total_amount_php),0),
    coalesce(sum(b.balance_amount_php),0)
  into booked_value_30d, outstanding_balance
  from plp_runtime.plp_bookings b
  where b.check_in between business_date and business_date + 30
    and upper(coalesce(b.status,'')) not in ('CANCELLED','CANCELED')
    and (allow_test_data or not private.plp_booking_is_test_v1(b.id));

  select coalesce(sum(p.amount_php),0)
  into paid_value_30d
  from plp_runtime.plp_payments p
  left join plp_runtime.plp_bookings b on b.id=p.booking_id
  where lower(coalesce(p.status,'')) in
      ('paid','succeeded','complete','completed')
    and p.paid_at >= business_date::timestamp
    and p.paid_at < (business_date + 30)::timestamp
    and (allow_test_data or (b.id is not null and not private.plp_booking_is_test_v1(b.id)));

  select count(*)::integer into universal_rooms
  from public.enterprise_hospitality_rooms r
  where r.organization_id=prop.organization_id;

  select count(*)::integer into universal_reservations
  from public.enterprise_hospitality_reservations r
  where r.organization_id=prop.organization_id;

  select count(*)::integer into universal_stays
  from public.enterprise_hospitality_stays s
  where s.organization_id=prop.organization_id;

  select count(*)::integer into universal_housekeeping
  from public.enterprise_hospitality_housekeeping_jobs h
  where h.organization_id=prop.organization_id;

  select count(*)::integer into universal_guest_profiles
  from public.enterprise_hospitality_guest_profiles g
  where g.organization_id=prop.organization_id;

  select count(*)::integer into universal_folios
  from public.enterprise_hospitality_folios f
  where f.organization_id=prop.organization_id;

  return jsonb_build_object(
    'schemaVersion','plp.resort.command-center.v1',
    'generatedAt',clock_timestamp(),
    'businessDate',business_date,
    'rooms',rooms,
    'stays',stays,
    'experienceSignals',experience_signals,
    'roomPulse',jsonb_build_object(
      'total',rooms_total,
      'occupied',case when live_operational_data_available then rooms_occupied else null end,
      'available',case when live_operational_data_available then greatest(rooms_total-rooms_occupied,0) else null end,
      'arriving',case when live_operational_data_available then rooms_arriving else null end,
      'departing',case when live_operational_data_available then rooms_departing else null end
    ),
    'operations',jsonb_build_object(
      'openWork',open_tasks,
      'priorityWork',priority_tasks,
      'channelExceptions',case when live_operational_data_available then open_conflicts else null end
    ),
    'finance',jsonb_build_object(
      'bookedValue30dPhp',case when live_operational_data_available then booked_value_30d else null end,
      'outstandingBalancePhp',case when live_operational_data_available then outstanding_balance else null end,
      'paidValue30dPhp',case when live_operational_data_available then paid_value_30d else null end
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
      'liveOperationalDataAvailable',live_operational_data_available,
      'source',case when allow_test_data
        then 'existing PLP runtime + Universal hospitality records'
        else 'customer tenant + non-test PLP runtime + Universal hospitality records'
      end,
      'testDataQuarantined',not allow_test_data
    )
  );
end;
$$;

revoke execute on function public.plp_resort_command_center_v1()
  from public, anon;
grant execute on function public.plp_resort_command_center_v1()
  to authenticated;
