-- Extend the authenticated PLP enterprise bootstrap with a bounded guest
-- experience projection. Raw guest contact details remain server-side.
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

  select to_jsonb(c) into ctx
  from plp_runtime.plp_ai_business_context c
  limit 1;

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
  ) q;

  select exists(
    select 1
    from plp_runtime.plp_bookings b
    left join plp_runtime.plp_guests g on g.id=b.guest_id
    where lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
       or lower(coalesce(b.source,'')) like 'qa_%'
  ) into has_mock;


  select count(*)::integer
  into active_member_count
  from public.memberships m
  where m.organization_id=prop.organization_id
    and m.status::text='active';

  select count(*)::integer
  into staff_identity_count
  from plp_runtime.plp_staff_identities s
  where s.active=true;

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
    from plp_runtime.plp_staff_tasks
    order by updated_at desc
    limit 12
  ) t;

  return jsonb_build_object(
    'schemaVersion','plp.enterprise.mobile-bootstrap.v5',
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
      'state',prop.source_status,
      'observedAt',prop.source_observed_at,
      'message',prop.source_message
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
